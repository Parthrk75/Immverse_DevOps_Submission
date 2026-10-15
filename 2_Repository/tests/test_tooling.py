import pathlib, subprocess, sys, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import validate_tenants as vt, migration_lint as ml, capacity, fleet_rollout as fr

GOOD = dict(name="acme-eu", residency="eu", cloud="aws", region="eu-central-1",
            dr_region="eu-west-1", size="m", ring="ring1-small", slo=99.95)


class Residency(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(vt.validate_doc(GOOD, "acme-eu"), [])

    def test_eu_tenant_in_us_region_rejected(self):
        self.assertTrue(any("violates residency" in e for e in vt.validate_doc({**GOOD, "region": "us-east-1"}, "acme-eu")))

    def test_eu_dr_in_us_rejected(self):
        self.assertTrue(any("dr_region" in e for e in vt.validate_doc({**GOOD, "dr_region": "us-west-2"}, "acme-eu")))

    def test_same_dr_rejected(self):
        self.assertTrue(vt.validate_doc({**GOOD, "dr_region": "eu-central-1"}, "acme-eu"))

    def test_us_tenant_ok_with_us_failover(self):
        d = {**GOOD, "name": "us-one", "residency": "us", "region": "us-west-2", "dr_region": "us-east-1"}
        self.assertEqual(vt.validate_doc(d, "us-one"), [])

    def test_name_folder_mismatch(self):
        self.assertTrue(vt.validate_doc(GOOD, "other"))


class NewTenant(unittest.TestCase):
    def test_generates_and_validates(self):
        with tempfile.TemporaryDirectory() as d:
            r = subprocess.run([sys.executable, str(ROOT / "scripts/new_tenant.py"), "--name", "t-eu1",
                                "--residency", "eu", "--root", d], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            for f in ["gitops/clusters/tenants/t-eu1/tenant.yaml", "gitops/clusters/tenants/t-eu1/application.yaml",
                      "infra/stacks/tenants/t-eu1/main.tf", "infra/stacks/tenants/t-eu1/backend.tf"]:
                self.assertTrue((pathlib.Path(d) / f).exists(), f)
            r2 = subprocess.run([sys.executable, str(ROOT / "scripts/new_tenant.py"), "--name", "t-eu1",
                                 "--residency", "eu", "--root", d], capture_output=True, text=True)
            self.assertNotEqual(r2.returncode, 0)  # refuses duplicates

    def test_stack_scan_catches_us_region_in_eu_stack(self):
        with tempfile.TemporaryDirectory() as d:
            old = vt.STACK_DIR
            vt.STACK_DIR = pathlib.Path(d)
            (pathlib.Path(d) / "bad").mkdir()
            (pathlib.Path(d) / "bad" / "main.tf").write_text('region = "us-east-1"\n')
            try:
                self.assertTrue(vt.scan_stack("bad", "eu"))
            finally:
                vt.STACK_DIR = old


class MigrationLint(unittest.TestCase):
    def test_flags_destructive(self):
        for sql in ["ALTER TABLE a DROP COLUMN b;", "ALTER TABLE a RENAME COLUMN b TO c;",
                    "ALTER TABLE a ALTER COLUMN b SET NOT NULL;", "CREATE INDEX i ON a(b);", "TRUNCATE a;",
                    "ALTER TABLE a ADD COLUMN b int NOT NULL;"]:
            self.assertTrue(ml.lint_sql(sql), sql)

    def test_allows_expand(self):
        for sql in ["ALTER TABLE a ADD COLUMN b int;", "CREATE INDEX CONCURRENTLY i ON a(b);",
                    "ALTER TABLE a ADD COLUMN b int NOT NULL DEFAULT 0;"]:
            self.assertEqual(ml.lint_sql(sql), [], sql)

    def test_contract_label_bypass(self):
        self.assertEqual(ml.lint_sql("-- migration: contract\nALTER TABLE a DROP COLUMN b;"), [])


class Capacity(unittest.TestCase):
    def test_numbers(self):
        r = capacity.compute()
        self.assertEqual(r["api_pods_peak"], 68)
        self.assertGreater(r["client_conns_peak"], r["server_conns_with_pgbouncer"] * 4)  # pooler is mandatory
        self.assertGreaterEqual(r["worker_pods_peak_worst"] * 4, r["conc_worst_peak"])  # 60 s worst case covered


class Rollout(unittest.TestCase):
    D = "sha256:" + "a" * 64

    def test_rejects_tag(self):
        self.assertEqual(fr.run("latest", True, None, ""), 2)

    def test_complete(self):
        self.assertEqual(fr.run(self.D, True, None, ""), 0)

    def test_halts_on_failure(self):
        self.assertEqual(fr.run(self.D, True, "ring1-small", ""), 1)


class RepoState(unittest.TestCase):
    def test_all_repo_tenants_valid(self):
        self.assertEqual(vt.main(), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
