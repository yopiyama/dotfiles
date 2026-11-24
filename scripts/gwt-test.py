"""Run with python3 scripts/gwt-test.py (requires Git and Bash)."""

import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory


def test_open_pr_can_cancel_removal():
    gwt = Path(__file__).with_name('gwt.sh').resolve()
    with TemporaryDirectory() as directory:
        root = Path(directory)
        repo = root / 'repo'
        worktree = root / 'topic worktree'
        repo.mkdir()
        env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}',
                   GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)

        def git(*args):
            subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com', *args],
                           cwd=repo, env=env, capture_output=True, check=True)

        git('init', '-b', 'main')
        git('commit', '--allow-empty', '-m', 'initial')
        git('worktree', 'add', '-b', 'topic', str(worktree))

        # Initially merged in the picker; reopened by the time Ctrl-D is confirmed.
        fixtures = {
            'gh': '''case " $* " in
  *' branch1=topic '*) state=MERGED ;;
  *) state=OPEN ;;
esac
printf 'topic\\t%s\\t42\\n' "$state"
''',
            'fzf': '''if [ -e .git/picked ]; then cat >/dev/null; exit 1; fi
touch .git/picked
awk '/topic worktree$/ { print "ctrl-d"; print }'
''',
        }
        for command, body in fixtures.items():
            fixture = root / command
            fixture.write_text('#!/bin/bash\n' + body)
            fixture.chmod(0o755)

        result = subprocess.run(['/bin/bash', str(gwt)], cwd=repo, env=env, input='y\ny\n\n',
                                capture_output=True, text=True, encoding='utf-8', check=True, timeout=10)
        assert 'PR #42 が Open です' in result.stderr, result.stderr
        assert worktree.is_dir(), result.stderr
        git('show-ref', '--verify', 'refs/heads/topic')


if __name__ == '__main__':
    test_open_pr_can_cancel_removal()
