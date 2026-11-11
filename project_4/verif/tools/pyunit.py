#!/usr/bin/env python3
"""Corre los tests de unittest de una carpeta y escribe un renglón por test en el
formato común de la verificación: [ok ] / [MAL]. Uso: pyunit.py <carpeta de tests>"""
import os
import sys
import unittest


class Result(unittest.TextTestResult):
    def addSuccess(self, test):
        super().addSuccess(test)
        print(f"[ok ] {test.id()}")

    def _bad(self, test, err, kind):
        print(f"[MAL] {test.id()}: {kind}\n{self._exc_info_to_string(err, test)}")

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self._bad(test, err, "falla")

    def addError(self, test, err):
        super().addError(test, err)
        self._bad(test, err, "error")

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        print(f"[MAL] {test.id()}: salteado ({reason})")   # un test salteado no es un PASS


def main():
    tests = os.path.abspath(sys.argv[1])
    os.chdir(os.path.dirname(tests))
    suite = unittest.defaultTestLoader.discover(tests, top_level_dir=tests)
    with open(os.devnull, "w") as quiet:
        r = unittest.TextTestRunner(stream=quiet, resultclass=Result, verbosity=0).run(suite)
    sys.exit(0 if r.wasSuccessful() and r.testsRun and not r.skipped else 1)


if __name__ == "__main__":
    main()
