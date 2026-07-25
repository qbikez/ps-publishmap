# PowerShell Modules

[![Build status](https://ci.appveyor.com/api/projects/status/ex5pl1am2t9ojny7?svg=true)](https://ci.appveyor.com/project/qbikez/publishmap)

This repository contains PowerShell modules for declarative project configuration and automation.

- [**PublishMap**](src/publishmap/README.md) — processes hierarchical PowerShell hashtables into deployment and configuration profiles with inheritance and variable substitution.
- [**ConfigMap**](src/configmap/README.md) — builds on PublishMap to provide declarative build and configuration commands through `qbuild` and `qconf`.
