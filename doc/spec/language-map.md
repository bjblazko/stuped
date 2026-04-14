# Specification: Language Map

## File: `Stuped/Models/LanguageMap.swift`

## Overview

`LanguageMap` is a stateless enum (no instances) that maps file extensions to highlight.js language identifiers and preview types.

## Types

```swift
enum PreviewType {
    case markdown
    case html
    case image
}
```

## Methods

### `language(for fileExtension: String) -> String?`

Looks up the file extension (case-insensitive) in `extensionToLanguage` dictionary. Returns the highlight.js language identifier or `nil`.

### `language(for utType: UTType) -> String?`

Extracts `preferredFilenameExtension` from the `UTType` and delegates to the string-based overload.

### `isMarkdown(_ fileExtension: String) -> Bool`

Returns `true` if the extension is in `markdownExtensions`.

### `isImage(_ fileExtension: String) -> Bool`

Returns `true` if the extension is in `imageExtensions`.

### `previewType(for fileExtension: String) -> PreviewType?`

- Returns `.markdown` if in `markdownExtensions`.
- Returns `.html` if in `htmlExtensions`.
- Returns `.image` if in `imageExtensions`.
- Returns `nil` otherwise.

### `isPreviewable(_ fileExtension: String) -> Bool`

Returns `previewType(for:) != nil`.

## Extension Sets

### Markdown extensions

`md`, `markdown`, `mdown`, `mkd`, `mkdn`, `mdx`

### HTML extensions

`html`, `htm`, `xhtml`

### Image extensions

`png`, `jpg`, `jpeg`, `gif`, `bmp`, `tiff`, `tif`, `webp`, `heic`, `heif`, `ico`

## Language Mapping

~60 entries mapping extensions to highlight.js language identifiers:

| Category | Extensions | highlight.js ID |
|----------|-----------|-----------------|
| **Web** | html, htm, xhtml, xml, svg | `xml` |
| | css | `css` |
| | scss, sass | `scss` |
| | less | `less` |
| | js, mjs, cjs, jsx | `javascript` |
| | ts, tsx | `typescript` |
| | json | `json` |
| | graphql, gql | `graphql` |
| **Systems** | c, h | `c` |
| | cpp, cc, cxx, hpp, hxx | `cpp` |
| | m, mm | `objectivec` |
| | swift | `swift` |
| | rs | `rust` |
| | go | `go` |
| | zig | `zig` |
| **JVM** | java | `java` |
| | kt, kts | `kotlin` |
| | scala | `scala` |
| | groovy, gradle | `groovy` |
| | clj | `clojure` |
| **.NET** | cs | `csharp` |
| | fs | `fsharp` |
| | vb | `vbnet` |
| **Scripting** | py, pyw | `python` |
| | rb | `ruby` |
| | php | `php` |
| | pl, pm | `perl` |
| | lua | `lua` |
| | r, R | `r` |
| | jl | `julia` |
| | ex, exs | `elixir` |
| | erl, hrl | `erlang` |
| | hs, lhs | `haskell` |
| | ml, mli | `ocaml` |
| **Shell** | sh, bash, zsh, fish | `bash` |
| | ps1, psm1 | `powershell` |
| | bat, cmd | `dos` |
| **Config** | yaml, yml | `yaml` |
| | toml, ini, cfg | `ini` |
| | conf | `nginx` |
| | properties | `properties` |
| | env | `bash` |
| **Markup** | md, markdown, mdown, mkd | `markdown` |
| | tex, latex | `latex` |
| | rst | `plaintext` |
| **Database** | sql | `sql` |
| **Build** | dockerfile, docker | `dockerfile` |
| | makefile, mk | `makefile` |
| | cmake | `cmake` |
| | tf, hcl | `hcl` |
| | nix | `nix` |
| **Other** | diff, patch | `diff` |
| | proto | `protobuf` |
| | wasm, wat | `wasm` |
| | vim | `vim` |
| | el, lisp | `lisp` |
| | scm | `scheme` |
| | dart | `dart` |
| | v | `verilog` |
| | vhd, vhdl | `vhdl` |
