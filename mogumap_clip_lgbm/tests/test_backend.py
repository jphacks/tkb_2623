import base64
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import numpy as np
from PIL import Image
from fastapi.testclient import TestClient

import api
import ml
import recommend
from history import snapshot, valid_history
from policy import POLICY_VERSION, model_available, training_due
from training_worker import process_job


def records(count=6, user='demo'):
    stream = io.BytesIO()
    Image.new('RGB', (16, 16), 'red').save(stream, format='PNG')
    data = base64.b64encode(stream.getvalue()).decode()
    return [dict(user_id=user, place_id=f'p{i}', image_id=f'i{i}', image_base64=data,
                 category='和食', rating=1 + i % 5, rated_at=f'2026-10-{i + 1:02d}T12:00:00Z',
                 price_level=2, google_rating=4.0, review_count=10) for i in range(count)]


def status(count=6):
    return dict(training_policy=POLICY_VERSION, record_count=count, model_version='generation-1',
                trained_store_ids=[f'p{i}' for i in range(count)])


class PolicyTests(unittest.TestCase):
    def test_first_and_incremental_training(self):
        self.assertFalse(training_due(records(5), None))
        self.assertTrue(training_due(records(6), None))
        self.assertFalse(training_due(records(10), status()))
        self.assertTrue(training_due(records(11), status()))
        # Delete a trained record and add five: total rises only by four.
        self.assertTrue(training_due(records(11)[1:], status()))
        self.assertFalse(training_due(records(5), status(), force=True))
        self.assertTrue(training_due(records(6), {'record_count': 32}))

    def test_invalid_and_duplicate_records(self):
        rows = records()
        rows += [rows[0], {**rows[1], 'place_id': 'bad', 'image_base64': 'bad'}]
        self.assertEqual(len(valid_history(rows, 'demo')), 6)
        with self.assertRaises(ValueError):
            valid_history(records(user='other'), 'demo')
        rows[0]['image_base64'] = base64.b64encode(b'not an image').decode()
        self.assertEqual(len(valid_history(rows[:6], 'demo')), 5)

    def test_snapshot_has_versions_not_images(self):
        manifest = snapshot(records())
        self.assertNotIn('image_base64', manifest[0])
        self.assertEqual(len(manifest[0]['data_version']), 64)
        changed = records()
        changed[0]['rating'] = 5
        self.assertNotEqual(manifest[0]['data_version'], snapshot(changed)[0]['data_version'])


class ApiTests(unittest.TestCase):
    def setUp(self):
        api._request_times.clear()
        self.env = patch.dict('os.environ', {'AI_BACKEND_API_KEY': 'test-key'})
        self.env.start()
        self.client = TestClient(api.app)
        self.headers = {'X-API-Key': 'test-key'}

    def tearDown(self):
        self.env.stop()

    def request(self, count):
        return self.client.post('/recommend', headers=self.headers, json={
            'user_id': 'demo', 'history': records(count), 'free_text': '和食', 'lat': 35, 'lng': 139,
        })

    @patch('api.train_user', side_effect=AssertionError('no training in recommendations'))
    @patch('api.Repository')
    @patch('api.extract_conditions', return_value={'category': '和食'})
    @patch('api.search_candidates', return_value=[])
    @patch('api.gemini_recommend', return_value=[])
    def test_zero_to_five_always_gemini(self, gemini, search, extract, repo, train):
        for count in [0, 1, 5]:
            response = self.request(count)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()['mode'], 'gemini')
        repo.assert_not_called()
        train.assert_not_called()

    @patch('api.Repository')
    @patch('api.extract_conditions', return_value={})
    @patch('api.search_candidates', return_value=[])
    @patch('api.gemini_recommend', return_value=[])
    @patch('ml.has_model', return_value=True)
    @patch('api.with_candidate_photos', return_value=[])
    @patch('api.predict_for_user', return_value=[])
    def test_six_uses_published_model(self, predict, photos, has, gemini, search, extract, repo):
        repo.return_value.status.return_value = status()
        response = self.request(6)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['mode'], 'lightgbm')
        self.assertEqual(predict.call_args.kwargs['version'], 'generation-1')
        gemini.assert_not_called()

    @patch('api.Repository')
    @patch('api.extract_conditions', return_value={})
    @patch('api.search_candidates', return_value=[])
    @patch('api.gemini_recommend', return_value=[])
    @patch('ml.has_model', return_value=False)
    def test_missing_model_falls_back_and_requests_repair(self, has, gemini, search, extract, repo):
        repo.return_value.status.return_value = status()
        response = self.request(6)
        self.assertEqual(response.json()['mode'], 'gemini')
        repo.return_value.repair.assert_called_once_with('demo')

    @patch('api.Repository')
    @patch('api.extract_conditions', return_value={})
    @patch('api.search_candidates', return_value=[])
    @patch('api.gemini_recommend', return_value=[])
    def test_first_training_not_ready_or_legacy_model(self, gemini, search, extract, repo):
        for state in [None, {'record_count': 32}]:
            repo.return_value.status.return_value = state
            self.assertEqual(self.request(6).json()['mode'], 'gemini')

    def test_auth_rate_limit_and_invalid_coordinates(self):
        self.assertEqual(self.client.post('/recommend', json={}).status_code, 401)
        with patch('api.RATE_LIMIT_PER_MINUTE', 0):
            self.assertEqual(self.request(6).status_code, 429)
        response = self.client.post('/recommend', headers=self.headers, json={
            'user_id': 'demo', 'free_text': 'a', 'lat': 91, 'lng': 0,
        })
        self.assertEqual(response.status_code, 422)

    def test_train_endpoint_does_not_publish(self):
        with patch('api.train_user', return_value={'model_version': 'manual'}) as train, patch('api.Repository') as repo:
            response = self.client.post('/train', headers=self.headers,
                                        json={'user_id': 'demo', 'records': records()})
            self.assertEqual(response.status_code, 200)
            train.assert_called_once()
            repo.assert_not_called()


class GeminiTests(unittest.TestCase):
    def test_only_real_candidates_and_finite_ratings(self):
        candidate = {**records()[0], 'name': 'real-name'}
        for value in [
            {'place_id': 'unknown', 'predicted_rating': 4},
            {'place_id': 'p0', 'predicted_rating': 6},
            {'place_id': 'p0', 'predicted_rating': float('nan')},
            {'place_id': 'p0', 'predicted_rating': True},
        ]:
            with patch('recommend.generate_json', return_value={'predictions': [value]}):
                with self.assertRaises(ValueError):
                    recommend.gemini_recommend('a', records(), [candidate])
        with patch('recommend.generate_json', return_value={'predictions': [
            {'place_id': 'p0', 'predicted_rating': 4.2, 'name': 'fabricated'}
        ]}) as generate:
            result = recommend.gemini_recommend('a', records(), [candidate])
            self.assertEqual(result[0]['name'], 'real-name')
            self.assertNotIn('image_base64', generate.call_args.args[0])
        with patch('recommend.generate_json', return_value={'predictions': [
            {'place_id': 'p0', 'predicted_rating': 4}, {'place_id': 'p0', 'predicted_rating': 4}
        ]}):
            with self.assertRaises(ValueError):
                recommend.gemini_recommend('a', [], [candidate])

    def test_dish_features_of_recent_stores_are_sent(self):
        history = records(12)
        for i, row in enumerate(history):
            row['dish_features'] = [{'caption': f'dish{i}-a'}, {'caption': f'dish{i}-b'}]
        history[11]['dish_features'] = []  # 未解析の店は飛ばして次の店を使う
        history[10]['dish_features'] = ['broken', {'caption': 'dish10-a'}]
        candidate = {**records()[0], 'name': 'real-name'}
        with patch('recommend.generate_json', return_value={'predictions': []}) as generate:
            recommend.gemini_recommend('a', history, [candidate])
        payload = json.loads(generate.call_args.args[0].split('\n', 1)[1])
        dishes = payload['rated_dishes']
        self.assertEqual(len(dishes), recommend.MAX_DISH_STORES)
        self.assertEqual(dishes[0]['dishes'], [{'caption': 'dish10-a'}])
        self.assertEqual(dishes[1]['dishes'], [{'caption': 'dish9-a'}, {'caption': 'dish9-b'}])
        self.assertEqual(dishes[1]['rating'], history[9]['rating'])
        self.assertEqual(dishes[-1]['dishes'][0]['caption'], 'dish1-a')
        with patch('recommend.generate_json', return_value={'predictions': []}) as generate:
            recommend.gemini_recommend('a', records(), [candidate])
        self.assertEqual(json.loads(generate.call_args.args[0].split('\n', 1)[1])['rated_dishes'], [])


class WorkerTests(unittest.TestCase):
    def test_success_uses_snapshot_and_fenced_publication(self):
        repo = Mock()
        repo.history.return_value, repo.status.return_value = records(), None
        repo.rpc.return_value = True
        with patch('ml.train_user', return_value={'model_version': 'job-1'}) as train:
            result = process_job(repo, {'id': 'job-1', 'user_id': 'demo', 'repair_requested': False})
        self.assertEqual(result['outcome'], 'succeeded')
        self.assertEqual(train.call_args.kwargs['version'], 'job-1')
        snapshots = [c for c in repo.rpc.call_args_list if 'p_snapshot' in c.kwargs]
        self.assertEqual(len(snapshots[0].kwargs['p_snapshot']), 6)

    def test_failed_download_does_not_train_or_publish(self):
        repo = Mock()
        repo.history.side_effect = TimeoutError('secret upstream text')
        with patch('ml.train_user') as train:
            result = process_job(repo, {'id': 'job-1', 'user_id': 'demo', 'repair_requested': False})
        self.assertEqual(result['error_code'], 'TimeoutError')
        train.assert_not_called()
        self.assertEqual(repo.rpc.call_args.kwargs['p_outcome'], 'failed')

    def test_lost_publication_never_reports_success(self):
        repo = Mock()
        repo.history.return_value, repo.status.return_value = records(), None
        repo.rpc.side_effect = [True, False, False]
        with patch('ml.train_user', return_value={}):
            result = process_job(repo, {'id': 'job-1', 'user_id': 'demo', 'repair_requested': False})
        self.assertEqual(result['outcome'], 'failed')

    def test_four_new_records_skip(self):
        repo = Mock()
        repo.history.return_value, repo.status.return_value = records(10), status()
        repo.rpc.return_value = True
        with patch('ml.train_user') as train:
            result = process_job(repo, {'id': 'job-1', 'user_id': 'demo', 'repair_requested': False})
        self.assertEqual(result['outcome'], 'skipped')
        train.assert_not_called()


class LocalModelTests(unittest.TestCase):
    def test_real_lightgbm_roundtrip_with_frozen_embedding_fixture(self):
        rows = records()
        rng = np.random.default_rng(42)
        vectors = {r['image_id']: rng.normal(size=512) for r in rows}
        vectors = {key: val / np.linalg.norm(val) for key, val in vectors.items()}
        with tempfile.TemporaryDirectory() as temp, patch('ml.embed_records', return_value=vectors):
            folder = Path(temp)
            stats = ml.train_user('demo', rows, version='test-1', output_dir=folder)
            self.assertEqual(stats['feature_count'], 533)
            self.assertGreater(stats['model_size_bytes'], 0)
            self.assertTrue(Path(stats['model_path']).exists())
            predictions = ml.predict_for_user('demo', rows, rows[:2], version='test-1', output_dir=folder)
            self.assertEqual(len(predictions), 2)
            self.assertTrue(all(1 <= r['predicted_rating'] <= 5 for r in predictions))
            self.assertEqual(stats['training_policy'], POLICY_VERSION)
            self.assertEqual(len(list(folder.rglob('*.joblib'))), 1)


if __name__ == '__main__':
    unittest.main()
