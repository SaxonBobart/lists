"""Exercise publishing guards against isolated real Git repositories."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("checkpoint", Path(__file__).parents[1] / "agent-checkpoint.py")
checkpoint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checkpoint)


class CheckpointGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run_git("init", "-b", "dev")
        self.run_git("config", "user.email", "fixture@example.invalid")
        self.run_git("config", "user.name", "Fixture")
        self.run_git("remote", "add", "origin", "https://github.com/SaxonBobart/lists.git")
        (self.root / "app.swift").write_text("// fixture\n")
        self.run_git("add", "app.swift")
        self.run_git("commit", "-m", "fixture")

    def run_git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], check=True, capture_output=True)

    def test_development_scope_is_accepted_without_mutation(self):
        before = checkpoint.git(self.root, "status", "--porcelain")
        self.assertEqual(checkpoint.validate(self.root, ["app.swift"]), ("dev", ["app.swift"]))
        self.assertEqual(checkpoint.git(self.root, "status", "--porcelain"), before)

    def test_main_is_never_automatically_published(self):
        self.run_git("checkout", "-b", "main")
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.validate(self.root, ["app.swift"])

    def test_existing_staging_is_preserved(self):
        (self.root / "app.swift").write_text("// somebody else's edit\n")
        self.run_git("add", "app.swift")
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.validate(self.root, ["app.swift"])
        self.assertEqual(checkpoint.git(self.root, "diff", "--cached", "--name-only"), "app.swift")

    def test_wrong_remote_is_rejected(self):
        self.run_git("remote", "set-url", "origin", "https://github.com/elsewhere/project.git")
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.validate(self.root, ["app.swift"])

    def test_broad_or_escaping_paths_are_rejected(self):
        for path in [".", "..", "../outside", str(self.root / "app.swift"), ":(glob)**"]:
            with self.subTest(path=path), self.assertRaises(checkpoint.CheckpointError):
                checkpoint.validate(self.root, [path])

    def test_credentials_inside_explicit_directory_are_rejected(self):
        (self.root / "config").mkdir()
        (self.root / "config" / "signing.p8").write_text("fixture, not a real key")
        with self.assertRaises(checkpoint.CheckpointError):
            checkpoint.validate(self.root, ["config"])


if __name__ == "__main__":
    unittest.main()
