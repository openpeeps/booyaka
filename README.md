<p align="center">
  <img src="https://github.com/openpeeps/booyaka/blob/main/.github/booyaka.png" width="90px" height="90px" alt="Booyaka Logo"><br>
  👻 Booyaka &mdash; A fast documentation generator for cool kids!<br>
  Compiled &bullet; Lightweight &bullet; Fast &bullet; 👑 Written in Nim language
</p>

<p align="center">
  <code>nimble install booyaka</code> | <a href="https://github.com/openpeeps/booyaka/releases">Download from GitHub</a>
</p>

<p align="center">
  <a href="https://github.com/">API reference</a><br>
  <img src="https://github.com/openpeeps/booyaka/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/booyaka/workflows/docs/badge.svg" alt="Github Actions">
</p>

<p align="center">
  <img src="https://github.com/openpeeps/booyaka/blob/main/.github/booyaka_readme.jpg" width="100%" alt="Booyaka Documentation Preview"><br>
</p>

## 😍 Key Features
- 🔥 **Compiled**, extremely **lightweight**, **super fast** and... 🤩 **SELF-HOSTED!**
- 🌍 **Cross-platform** CLI application (Linux, macOS, Windows)
- 📄 Generate documentation websites from **Markdown files**
- 📚 **Build online book websites** directly from Markdown
- ⚡️ Dynamic Site Generation with **embedded HTTP server**
- 🔎 Search Functionality with Offline capabilities powered by IndexedDB
- 🔁 Browser Sync & **Live Reload**
- 🤔 **YAML** or **JSON** based configuration? Choose your favorite! 😻
- 📲 Responsive & Clean UI 💪 Powered by **Bootstrap 5**
- 💅 Customizable UI themes
- 🧩 Easy to extend with custom **CSS** and **JS**
- 🎩 **Open Source** | **AGPLv3** License
- 👑 Written in **Nim language** | **Made by Humans from OpenPeeps**

> [!NOTE]
> Booyaka is still in active development. Expect frequent updates and new features as we work towards a stable release.

## About
Booyaka is a documentation site generator that takes a directory of Markdown files and generates a
fully functional documentation website, then serves it dynamically using an embedded HTTP server.
It is designed to be simple, fast, and easy to use.

Booyaka is written in [Nim language](https://github.com/nim-lang), a statically typed compiled systems
programming language that combines the performance and low-level control of C with the expressiveness
and ease of use of modern languages like Python and Ruby. [Learn more about Nim](https://nim-lang.org).

## 📦 Installation
Download the precompiled binaries from the [releases page](https://github.com/openpeeps/booyaka/releases)
or use `nimble` to build from source. Read the [Nim installation guide](https://nim-lang.org/install.html)
if you don't have Nim installed.


### Prerequisites
- [Nim](https://nim-lang.org/install.html) >= 2.0
- Libevent

```
nimble install booyaka
```

## 🚀 Getting Started

To generate a documentation website using Booyaka, run the following command in your terminal,
replacing `<directory>` with the path of  the next directory you want to create the documentation site from:

```
booyaka new <directory>
```

Booyaka will create a new directory with the necessary files and folders to get started. You can then navigate to the newly created directory and start the embedded HTTP server by running:

```
booyaka run --port:8000 --sync
```

Open your web browser and go to `http://localhost:8000` to view your documentation site.

## Roadmap
Here are some planned features and improvements for future releases:

- [ ] UI Mobile-optimized
- [ ] UI Dark/Light mode toggle
- [ ] Inline Markdown Editor for content editing
- [ ] Embed [Tabler Icons](https://tabler.io/icons) directly into Booyaka for easier icon usage
- [ ] PDF/Offline Export
- [ ] Backend - Static site generation mode
- [ ] Backend - Feedback and Commenting System
- [ ] Authentication for private documentation
- [ ] Multi-language support

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/booyaka/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/booyaka/fork)
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)

### 🎩 License
AGPLv3 license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
