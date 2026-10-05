# Vendored: hardcaml-latency

`src/` is an unmodified copy of `src/` from the separate repository
`~/prog/janestreet/hardcaml-latency` at commit f59e57a5a4da93ac69361e73343c5bea973bcdfb
("README: precise wording on Clocked_signal checks"), copied on 2026-10-05.

Do not edit it here. Change the library in its own repository and copy `src/` again,
updating the commit above. `diff --recursive` against that repository's `src/` at the
commit above must be empty.

The prototypes that use it reach it through a directory symlink named `src`
(`<prototype>/src -> ../../vendor/hardcaml_latency/src`), because each prototype is its
own dune project. The name matters: the library finds the design's own source line for an
error message by skipping call-stack frames whose file starts with `src/` (Hardcaml's and
its own). Under any other name, every `Delayed` error names `delayed.ml:29` instead of the
design's line.
