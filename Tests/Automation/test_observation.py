"""Reject stale or malformed simulator evidence, independently of app output."""
import importlib.util
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('observation', ROOT/'Scripts/assert_simulator_state.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
class ObservationTests(unittest.TestCase):
    def test_freshness_and_schema_are_required(self):
        valid = {'schemaVersion': 1, 'observedEpoch': 99.5}
        self.assertTrue(module.matches(valid, [], [], now=100))
        for change in [{'observedEpoch': 95}, {'observedEpoch': 102}, {'observedEpoch': float('nan')},
                       {'observedEpoch': True}, {'schemaVersion': 2}, {'schemaVersion': True}]:
            self.assertFalse(module.matches(valid | change, [], [], now=100))
        self.assertFalse(module.matches(valid, [], [], now=100, after=99.9))
    def test_nested_values_do_not_confuse_booleans_and_numbers(self):
        record = {'schemaVersion': 1, 'observedEpoch': 100, 'playback': {'ready': True, 'width': 512}, 'items': [4]}
        self.assertTrue(module.matches(record, [('playback.ready', True), ('items.0', 4)], [('playback.width', 1)], now=100))
        self.assertFalse(module.matches(record, [('playback.ready', 1)], [], now=100))
        self.assertFalse(module.matches(record, [], [('playback.ready', 1)], now=100))
        self.assertFalse(module.matches(record, [], [('playback.width', float('nan'))], now=100))
        self.assertFalse(module.matches(record, [('missing.field', 1)], [], now=100))
    def test_expression_rejects_malformed_paths(self):
        self.assertEqual(module.expression('playback.ready=true'), ('playback.ready', True))
        for value in ['missing', '=1', 'a..b=2', '../secret=1']:
            with self.assertRaises(Exception): module.expression(value)

class ScenarioEvidenceTests(unittest.TestCase):
    def test_results_require_schema_launch_identifier_and_scenario(self):
        spec = importlib.util.spec_from_file_location('scenes', ROOT/'Scripts/run_scene_checks.py')
        scenes = importlib.util.module_from_spec(spec); spec.loader.exec_module(scenes)
        valid = {'schemaVersion': 1, 'identifier': 'current-launch', 'scenario': 'mp4', 'status': 'passed'}
        self.assertTrue(scenes.completed_result(valid, 'current-launch', 'mp4'))
        self.assertTrue(scenes.completed_result(valid | {'status': 'failed'}, 'current-launch', 'mp4'))
        for record in [None, [], valid | {'schemaVersion': True}, valid | {'identifier': 'stale-launch'},
                       valid | {'scenario': 'hls'}, valid | {'status': 'running'}]:
            self.assertFalse(scenes.completed_result(record, 'current-launch', 'mp4'))
