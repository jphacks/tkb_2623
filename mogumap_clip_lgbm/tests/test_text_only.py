import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import api
from metadata import metadata_history
from test_backend import records, status


class TextOnlyTests(unittest.TestCase):
    def test_metadata_strips_images_and_preserves_dish_features(self):
        row = records(1)[0]
        row['image_path'] = '/not/a/real/image'
        row['image_base64'] = 'unreadable-and-must-not-be-decoded'
        row['dish_features'] = [{'caption': 'ramen'}]
        result = metadata_history([row], 'demo')
        self.assertEqual(len(result), 1)
        self.assertNotIn('image_base64', result[0])
        self.assertNotIn('image_path', result[0])
        self.assertEqual(result[0]['dish_features'], [{'caption': 'ramen'}])
        with self.assertRaises(ValueError):
            metadata_history([row], 'other-user')

    @patch('api.valid_history', side_effect=AssertionError('Gemini must not decode images'))
    @patch('api.Repository')
    @patch('api.extract_conditions', return_value={})
    @patch('api.search_candidates', return_value=[])
    @patch('api.gemini_recommend', return_value=[])
    @patch('api.with_candidate_photos', side_effect=AssertionError('Gemini must not fetch photos'))
    def test_gemini_does_not_fetch_or_validate_images(self, photos, gemini, search, extract, repo, validate):
        repo.return_value.status.return_value = None
        client = TestClient(api.app)
        with patch.dict('os.environ', {'AI_BACKEND_API_KEY': 'test'}):
            for count in [0, 1, 5, 6]:
                rows = [{k: v for k, v in r.items() if k != 'image_base64'} for r in records(count)]
                api._request_times.clear()
                response = client.post('/recommend', headers={'X-API-Key': 'test'}, json={
                    'user_id': 'demo', 'free_text': '和食', 'lat': 35, 'lng': 139, 'history': rows,
                })
                self.assertEqual(response.status_code, 200, response.text)
                self.assertEqual(response.json()['mode'], 'gemini')
                self.assertTrue(all('image_base64' not in r for r in gemini.call_args.args[1]))
        repo.return_value.history.assert_not_called()
        validate.assert_not_called()
        photos.assert_not_called()

    @patch('ml.has_model', return_value=True)
    @patch('api.Repository')
    @patch('api.extract_conditions', return_value={})
    @patch('api.search_candidates', return_value=[])
    @patch('api.gemini_recommend', return_value=[])
    def test_storage_outage_falls_back_without_retraining(self, gemini, search, extract, repo, has_model):
        repo.return_value.status.return_value = status()
        repo.return_value.history.side_effect = TimeoutError('temporary storage failure')
        api._request_times.clear()
        with patch.dict('os.environ', {'AI_BACKEND_API_KEY': 'test'}):
            response = TestClient(api.app).post('/recommend', headers={'X-API-Key': 'test'}, json={
                'user_id': 'demo', 'free_text': '和食', 'lat': 35, 'lng': 139, 'history': records(6),
            })
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['mode'], 'gemini')
        repo.return_value.repair.assert_not_called()



if __name__ == '__main__':
    unittest.main()
