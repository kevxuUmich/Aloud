# Aloud

Reads your text files to you.
macOS 26, Swift.

    brew install watchexec xcodegen
    make watch      # rebuild and relaunch on save
    make gallery    # the component page
    make test
    make check

`xcodegen generate` writes `Aloud.xcodeproj` from `project.yml`, which is the sandboxed, signable app target; the project itself is not in git.

v1 reads `.md`, `.txt` and `.pdf` from folders you point it at and never copies them; it takes text in by paste, by drop, by Import files and by a global hotkey that reads the clipboard and starts playing; it searches the whole vault by title and body, shows it as a grid or a list, and offers Play, Mark finished, Reveal in Finder and Move to Trash on any card; it speaks with the system voices through a popover that previews and tags each one, at eight speeds, with the sentence and the word highlighted and a click on a sentence seeking to it; it edits `.md` and `.txt` in place, saving on Done, on blur and on Cmd+S; it remembers where you stopped in every document and marks it Finished at the end; and it keeps playing with the window closed, through a menu-bar player, the media keys and the Now Playing widget, with Settings for the vault folders, the default voice and speed, the hotkey, whether code blocks are skipped, launch at login and whether the menu-bar item is shown.

The sandboxed, signable app needs Xcode 26: `xcodegen generate`, open `Aloud.xcodeproj`, and sign with your team.
Launch at login goes through `SMAppService` and works only in that signed, bundled build.

`.build/Aloud.app/Contents/MacOS/Aloud --say path/to/file.md` speaks a file from the terminal.
`.build/Aloud.app/Contents/MacOS/Aloud --silent` runs with a fake voice for UI work.
