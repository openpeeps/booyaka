# Custom syntax specs for backend code highlighting (SweetSyntax)
#
# Drop `*.yaml` language specs in this directory to highlight fenced code
# blocks beyond SweetSyntax built-ins (js, py, nim, c, rust, ruby, php,
# go, d, css, md). Each file registers under its basename plus every
# extension declared in the spec, e.g. `timl.yaml` highlights ```timl.
#
# Project themes override the `default` theme per filename:
# `<project>/themes/<active>/syntax/<name>.yaml` wins over
# `<project>/themes/default/syntax/<name>.yaml`.
#
# Changes require restarting `booyaka start` (specs load once at startup).
# Unknown languages and lexer failures fall back to plain escaped code.
