# Contributing

Thanks for your interest in RubberDuck.

## Getting set up

Requires Xcode 16+ and macOS 15.2+ SDK.

```bash
git clone https://github.com/mblode/rubber-duck.git
cd rubber-duck
open RubberDuck.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -scheme RubberDuck -configuration Debug build -derivedDataPath /tmp/rubber-duck-build
```

## Making changes

1. Fork the repo and create a branch
2. Make your changes
3. Test locally — build and run the app from Xcode or the CLI
4. Open a pull request

## Reporting bugs

Open an [issue](https://github.com/mblode/rubber-duck/issues) with steps to reproduce.
