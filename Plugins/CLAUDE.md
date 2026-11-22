# Plugins

`SafeDIGenerator` compiles `SafeDICore`'s `FilePathSpelling.swift` and `OutputFileNaming.swift` and `SafeDIToolLibrary`'s `PluginTargetGraph.swift` through symbolic links: they are the same sources, and `Scripts/changed-line-coverage.sh` counts a line executed when either copy ran it.
