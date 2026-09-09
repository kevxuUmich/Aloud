# Aloud

Reads your text files to you.
macOS 26, Swift.

    brew install watchexec xcodegen
    make watch      # rebuild and relaunch on save
    make gallery    # the component page
    make test
    make check

`xcodegen generate` writes `Aloud.xcodeproj` from `project.yml`, which is the sandboxed, signable app target; the project itself is not in git.

`.build/Aloud.app/Contents/MacOS/Aloud --say path/to/file.md` speaks a file from the terminal.
`.build/Aloud.app/Contents/MacOS/Aloud --silent` runs with a fake voice for UI work.
