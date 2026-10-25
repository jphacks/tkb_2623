import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import train_cli
from repository import Repository
from test_backend import records, status


class CliTests(unittest.TestCase):
    @patch('repository.Repository')
    @patch('ml.train_user')
    def test_dry_run_never_writes_or_trains(self, train, repo):
        repo.return_value.history.return_value = records()
        repo.return_value.status.return_value = None
        with patch('sys.argv', ['train_cli', '--source', 'supabase', '--user-id', 'demo', '--dry-run']), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(train_cli.main(), 0)
        train.assert_not_called()
        repo.return_value.rpc.assert_not_called()

    @patch('repository.Repository')
    @patch('ml.train_user', return_value={'model_version': 'manual'})
    def test_force_default_output_is_isolated(self, train, repo):
        repo.return_value.history.return_value = records()
        repo.return_value.status.return_value = status()
        with patch('sys.argv', ['train_cli', '--source', 'supabase', '--user-id', 'demo', '--force']), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(train_cli.main(), 0)
        self.assertIn('artifacts/manual', str(train.call_args.kwargs['output_dir']))
        repo.return_value.rpc.assert_not_called()

    @patch('repository.Repository')
    @patch('ml.train_user', return_value={'model_version': 'manual'})
    def test_gcp_test_uses_nonproduction_prefix(self, train, repo):
        repo.return_value.history.return_value = records()
        repo.return_value.status.return_value = None
        with patch.dict('os.environ', {'MODEL_BUCKET': 'test'}), patch('sys.argv', [
            'train_cli', '--source', 'supabase', '--user-id', 'demo', '--force', '--gcs-test'
        ]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(train_cli.main(), 0)
        self.assertIsNone(train.call_args.kwargs['output_dir'])
        self.assertEqual(train.call_args.kwargs['storage_prefix'], 'manual-tests')
        repo.return_value.rpc.assert_not_called()

    @patch('repository.Repository')
    @patch('ml.train_user')
    def test_force_cannot_bypass_minimum(self, train, repo):
        repo.return_value.history.return_value, repo.return_value.status.return_value = records(5), None
        with patch('sys.argv', ['train_cli', '--source', 'supabase', '--user-id', 'demo', '--force']), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                train_cli.main()
        self.assertEqual(error.exception.code, 2)
        train.assert_not_called()
        repo.return_value.rpc.assert_not_called()

    @patch('repository.Repository')
    @patch('training_worker.process_job', return_value={'outcome': 'succeeded'})
    def test_publish_goes_through_claim_and_worker(self, process, repo):
        repo.return_value.history.return_value, repo.return_value.status.return_value = records(), None
        repo.return_value.rpc.side_effect = [None, [{'id': 'job', 'user_id': 'demo', 'repair_requested': True}]]
        with patch('sys.argv', ['train_cli', '--source', 'supabase', '--user-id', 'demo', '--force', '--publish']), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(train_cli.main(), 0)
        self.assertEqual(repo.return_value.rpc.call_args.args[0], 'ai_claim_training')
        process.assert_called_once()


class RepositoryTests(unittest.TestCase):
    def test_first_photo_order_and_download_failures(self):
        import requests
        repo = Repository('https://example.invalid', 'not-a-key')
        row = records()[0]
        import base64
        data = base64.b64decode(row['image_base64'])
        store = dict(id='p0', user_id='demo', category='和食', reputation=4, created_at=row['rated_at'],
                     image=[{'id': 'later', 'image': 'later.png', 'created_at': '2026-02-01'},
                            {'id': 'first', 'image': 'first.png', 'created_at': '2026-01-01'}])
        meta, photo = Mock(), Mock()
        meta.json.return_value, photo.content = [store], data
        with patch.object(repo, 'request', side_effect=[meta, photo]) as request:
            result = repo.history('demo')
        self.assertEqual(result[0]['image_id'], 'first')
        self.assertTrue(request.call_args.args[1].endswith('/first.png'))
        with patch.object(repo, 'request', side_effect=[meta, requests.Timeout('temporary')]):
            with self.assertRaises(requests.Timeout):
                repo.history('demo')


if __name__ == '__main__':
    unittest.main()
