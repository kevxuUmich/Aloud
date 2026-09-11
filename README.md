<p align="center">
  <img src="App/Icon/Aloud-1024.png" width="128" alt="Aloud">
</p>

<h1 align="center">Aloud</h1>

<p align="center"><strong>Your notes, read to you. Nothing leaves your Mac.</strong></p>

<p align="center">Point it at the folders you already have. Press one key. Listen.</p>

---

## The pile you keep meaning to read

There is a folder on your Mac that keeps growing.
Meeting notes.
Chat transcripts.
Papers you saved for the weekend.
The Markdown you wrote at midnight and never looked at again.

Reading it takes a chair, a screen, and an hour you do not have.
Every app that offers to read it aloud wants the files uploaded first, then an account, then a subscription.

Your Mac already has the voices.
It just needed something to hand them your files.

## One key, from anywhere

Copy a paragraph in any app.
Press **Option+Space**.

A small card appears under the menu bar with the text's title, its length, and a Play button.
Space plays it.
Nothing is written until you say so, and text you have played before is the same note, never a duplicate.

Press Option+Space again while it is reading and it pauses.
Press Space and it carries on.
You never have to find the window.

## It reads what you have, where it is

Aloud reads `.md`, `.txt`, and `.pdf` straight out of the folders you point it at.
It never copies them, never uploads them, and never asks you to import a library.
An Obsidian vault works as it stands.

Markdown is read as prose.
Headings, lists, links, and tables come out the way a person would say them.
Code blocks can be skipped with one setting.
PDFs lose their running headers, page numbers, and hyphen breaks before the voice ever sees them.

## Made for listening, not just playing

- **The text follows the voice.**
  The sentence being read is highlighted, and so is the word.
  Click any sentence to jump to it.
- **It remembers where you stopped.**
  Every document, every time.
  Reach the end and it is marked Finished.
- **Eight speeds, from 0.75x to 3x.**
  A change is heard on the sentence you are in, not the next file.
- **Every voice on the Mac, previewed before you pick it.**
  Seven recommended voices sit at the top of the picker with their download sizes.
- **Skip back and forward 15 seconds** and always land on a sentence boundary, never mid-word.
- **Edit in place.**
  Fix a typo in a note without leaving the reader.
  Saves on Done, on blur, and on Cmd+S.

## Keep working. It keeps reading.

Close the window and the reading goes on.
There is a player in the menu bar, the media keys work, AirPods work, and the Now Playing card in Control Center shows what is playing.
Pull your headphones out and it pauses.

## Search everything you have ever saved

Titles and full text, across every folder, as you type.
A grid or a list, with Play, Mark finished, Reveal in Finder, and Move to Trash on every card.

## What it will never do

- Ask you to make an account.
- Send a file, a title, or a keystroke anywhere.
- Charge you.

Aloud is free, open source under the MIT license, and runs entirely on your Mac.

## Try it

Aloud is built for macOS 26 and written in Swift.

    git clone https://github.com/kevxuUmich/Aloud.git
    cd Aloud
    make dev

That builds the app and opens it.
Add a folder, or copy some text and press Option+Space.

### For the signed build

The sandboxed, signable app needs Xcode 26.

    brew install xcodegen
    xcodegen generate

Open `Aloud.xcodeproj` and sign with your team.
Launch at login goes through `SMAppService` and works only in that signed, bundled build.
The project file is written from `project.yml` and is not in git.

### Developing

    brew install watchexec xcodegen
    make watch      # rebuild and relaunch on save
    make gallery    # the component page
    make test
    make check

Four library targets hold every rule about text, timing, and geometry, each with its own tests, and the app only draws.
Swift 6 with strict concurrency, so a data race is a compile error.

    .build/Aloud.app/Contents/MacOS/Aloud --say path/to/file.md   # speak a file from the terminal
    .build/Aloud.app/Contents/MacOS/Aloud --silent                # run with a fake voice for UI work
