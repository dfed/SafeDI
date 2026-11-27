# Step 2b value cells, for a Swift 6.4 compile

Four cells whose filled seam call step 2b lays out from node records, with fill builders declared at the top of the
fill body (lead ruling, entry 24). Each cell is two modules, `CellNFeature` (declares the seam) and `CellNApp` (fills it).
The generated files are checked in, so the compiler only needs the SafeDI runtime and macros from a checkout of 2.4.1.

    git -C <SafeDI checkout> worktree add <dir> 2.4.1
    SAFEDI_CHECKOUT=<dir> swift build -c release   # run in this folder; prints errors only on failure
    swift --version                                # report the compiler

Values against 2.4.1 already match under Swift 6.2 (Linux): classes B=4 of 4.
