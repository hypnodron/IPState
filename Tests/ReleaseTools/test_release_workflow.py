import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ReleaseWorkflowTests(unittest.TestCase):
    def check_release(self, releases, api_failure=False):
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        step = workflow.split('      - name: Check for an existing release\n', 1)[1]
        step = step.split('      - name:', 1)[0]
        script = textwrap.dedent(step.split('        run: |\n', 1)[1])
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            fixture = directory / 'releases.json'
            fixture.write_text(json.dumps(releases))
            output = directory / 'output'
            transport = directory / 'gh'
            transport.write_text(f'#!{sys.executable}\n' + '''
import json
import os
from pathlib import Path
import sys

if os.environ['API_FAILURE'] == '1':
    print('Authentication failed', file=sys.stderr)
    sys.exit(1)
releases = json.loads(Path(os.environ['RELEASE_FIXTURE']).read_text())
endpoint = sys.argv[2]
if '/releases/tags/' in endpoint:
    tag = endpoint.split('/releases/tags/', 1)[1]
    release = next((r for r in releases if r['tag_name'] == tag and not r['draft']), None)
    if release is None:
        print(json.dumps({'message': 'Not Found', 'status': '404'}))
        sys.exit(1)
    print(json.dumps(release))
elif endpoint.endswith('/releases?per_page=100'):
    assert '--paginate' in sys.argv
    assert sys.argv[sys.argv.index('--jq') + 1] == '.[] | .tag_name'
    for release in releases:
        print(release['tag_name'])
else:
    raise RuntimeError('Unexpected GitHub request')
''')
            transport.chmod(0o700)
            environment = dict(os.environ, PATH=f'{directory}:{os.environ["PATH"]}',
                GH_REPO='owner/IPState', GITHUB_REF_NAME='v1.0.0', GITHUB_OUTPUT=str(output),
                RELEASE_FIXTURE=str(fixture), API_FAILURE='1' if api_failure else '0')
            result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', script],
                env=environment, cwd=directory, capture_output=True, text=True, timeout=10)
            return result, output.read_text() if output.exists() else ''

    def test_existing_draft_prevents_a_second_release_build(self):
        result, output = self.check_release([dict(tag_name='v1.0.0', draft=True)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, 'exists=true\n')

    def test_existing_published_release_prevents_a_second_release_build(self):
        result, output = self.check_release([dict(tag_name='v1.0.0', draft=False)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, 'exists=true\n')

    def test_another_versions_draft_does_not_block_a_new_release(self):
        result, output = self.check_release([dict(tag_name='v0.11.0', draft=True)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, 'exists=false\n')

    def test_api_failure_stops_instead_of_treating_the_release_as_absent(self):
        result, output = self.check_release([], api_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, '')


if __name__ == '__main__':
    unittest.main()
