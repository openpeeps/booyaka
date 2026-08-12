<p align="center">
  <img src="https://github.com/openpeeps/booyaka/blob/main/.github/booyaka.png" width="90px" height="90px" alt="Booyaka Logo"><br>
  Booyaka &mdash; A fast documentation generator for cool kids!<br>
  Compiled &bullet; Lightweight &bullet; Fast &bullet; Written in Nim
</p>

<p align="center">
  <code>nimble install booyaka</code> | <a href="https://github.com/openpeeps/booyaka/releases">Download from GitHub</a>
</p>

<p align="center">
  <img src="https://github.com/openpeeps/booyaka/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/booyaka/workflows/docs/badge.svg" alt="Github Actions">
</p>

![Booyaka Homepage Preview](https://github.com/openpeeps/booyaka/blob/main/.github/booyaka_preview.png)

## Key Features
- Compiled, lightweight, and fast; fully self-hosted
- Cross-platform CLI application (Linux, macOS, Windows)
- Generate documentation websites from Markdown files
- Build online book-style websites directly from Markdown
- Embedded HTTP server with dynamic site generation
- Static site generation with the `build` command
- Client-side fuzzy search with offline support
- Browser Sync and Live Reload while writing documentation
- YAML or JSON based configuration
- Responsive UI powered by Bootstrap 5
- Light, dark, and system themes with a theme switcher
- Left and right sidebars: manual navigation or auto-generated table of contents
- Nested table of contents and bottom previous/next page navigation
- Configurable code syntax highlighting themes
- Lazy loading for iframes, videos, audio, and images
- Customizable with project CSS and JavaScript
- AI share buttons for ChatGPT, Claude, Gemini, and GitHub Copilot
- Optional Git-based versioning and contributors information
- Print-friendly layout for PDF export
- SEO metadata support
- Open Source | AGPLv3 License

> [!NOTE]
> Booyaka is still in active development. Expect frequent updates and new features as we work towards a stable release.

## About
Booyaka is a documentation site generator that takes a directory of Markdown files and generates a
fully functional documentation website, then serves it dynamically using an embedded HTTP server.
It can also export a complete static HTML website for hosting anywhere.
It is designed to be simple, fast, and easy to use.

Booyaka is written in [Nim language](https://github.com/nim-lang), a statically typed compiled systems
programming language that combines the performance and low-level control of C with the expressiveness
and ease of use of modern languages like Python and Ruby. [Learn more about Nim](https://nim-lang.org).

## Installation
Download the precompiled binaries from the [releases page](https://github.com/openpeeps/booyaka/releases)
or use `nimble` to build from source. Read the [Nim installation guide](https://nim-lang.org/install.html)
if you don't have Nim installed.

### Prerequisites
- [Nim](https://nim-lang.org/install.html) >= 2.2.10

```
nimble install booyaka
```

## Getting Started

Create a new Booyaka project by running the following command, replacing `<directory>` with the
path of the directory you want to create the documentation site from:

```
booyaka new <directory>
```

Booyaka will create a new directory with the necessary files and folders to get started. Navigate to
the newly created directory and start the embedded HTTP server:

```
cd <directory>
booyaka start --port:8000 --sync
```

Open your web browser and go to `http://localhost:8000` to view your documentation site. The `--sync`
flag enables Browser Sync and Live Reload while you write.

To generate a static HTML website for hosting, run:

```
booyaka build <directory>
```

## CLI
| Command | Description |
|---|---|
| `booyaka new <directory>` | Create a new Booyaka project (`--json` to generate a JSON config) |
| `booyaka start <directory>` | Start the embedded HTTP server (`--port`, `--sync`) |
| `booyaka build <directory>` | Generate a static HTML website |

## Configuration
Booyaka reads a `booyaka.config.yaml`, `booyaka.config.yml`, or `booyaka.config.json` file in the
project directory. It supports metadata (title, description, keywords, logo), appearance (themes,
layout widths, theme switcher), header (search, notification banner), content (lazy loading, code
highlighting, bottom navigation), navigation (navbar, sidebar sections), footer, and optional
Git-based versioning and contributors information.

## Roadmap
Here are some planned features and improvements for future releases:

- [ ] UI mobile-optimized refinements
- [ ] Inline Markdown editor for content editing
- [ ] Feedback and commenting system
- [ ] Authentication for private documentation
- [ ] Multi-language support

### Contributions & Support
- Found a bug? [Create a new Issue](https://github.com/openpeeps/booyaka/issues)
- Want to help? [Fork it!](https://github.com/openpeeps/booyaka/fork)

|  |  |
|---|---|
| <a href="https://opencode.ai/go?ref=BHMEEK48QX"><img src="https://github.com/openpeeps/pistachio/blob/main/.github/opencode.png" alt="OpenCode"></a> | Switch to **Open-Source LLMs** via OpenCode GO, choosing from a variety of powerful models such as DeepSeek, Qwen, Kimi, GLM-5, MiniMax, MiMo. [Use our referral link to get started!](https://opencode.ai/go?ref=BHMEEK48QX)|

### License
AGPLv3 license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
