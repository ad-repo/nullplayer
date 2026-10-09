# Audion faces guide

NullPlayer can wear the faces of Panic's Audion, the classic Mac MP3 player. A face is a folder
holding `index.json` and a set of PNGs; Panic published the whole archive, converted to that format,
in 2021. NullPlayer does not bundle any faces. With no face selected it shows its own plain Audion
player, which has a **Load Face…** button.

Faces are drawn by a port of Panic's FaceKit viewer (GPL-3.0-or-later, Copyright 2020-2021 Panic
Inc.), so a face looks the way Panic's own code draws it.

## Install, select, and remove

1. Choose **Skins › Audion Faces › Get More Faces...** to open Panic's download page, and download
   the archive.
2. Choose **Load Face...** (or **Load Face…** on the plain player) and pick a face folder, or a
   `.zip` holding one or more face folders, such as Panic's archive. NullPlayer checks every face
   before copying it into `~/Library/Application Support/NullPlayer/AudionFaces/`, then switches to
   it. **Open Faces Folder...** shows that folder.
3. Choose any installed face from **Skins › Audion Faces**. Past 40 faces the list is grouped into
   A–Z submenus; the letter holding the current face is checked.
4. **Remove “name”...** deletes NullPlayer's copy of the current face and returns to the plain
   player. It never touches the file you downloaded.

## The face's buttons

| Button | Does |
|---|---|
| play / pause, stop | play, pause, stop |
| rewind / fast forward | previous / next track |
| volume | a volume slider pops up beside the button |
| the time | click it for a position slider; scrubbing pauses, and playback resumes when you let go |
| playlist | shows or hides the playlist |
| mode | shows or hides the Library Browser |
| eject | Open Files… |
| info | **About Playing…** (the track's info) or **About This Face…** (the face's credits) |
| close | quits NullPlayer, like every NullPlayer player's close button |

Buttons Panic's viewer left disabled (eject, close, info, playlist, mode) all work here. Right-click
the face for NullPlayer's usual menu; the keyboard shortcuts are the Original player's. Shuffle and
repeat are in the **Playback** menu.

The two numbers before the clock are the track's position in the playlist. The NET light shows for
radio and server streams, MP3 for a local file. UI Size in the Windows menu scales the face from 50%
to 300%.

## NullPlayer's windows beside a face

The playlist, EQ, Library Browser and the visualizers take their colours from the face: the
background from its display, the text from its own text colours, adjusted where needed so the text
stays readable. They dock to the face and to each other.

## Recovery

A face that is missing, damaged or rejected leaves NullPlayer in Audion mode on the plain player,
with a message naming the problem. Load the face again or choose another. One malformed element
does not reject a face: NullPlayer drops that element and draws the rest.

For a reproduction, advanced users can open a face folder directly:

```bash
/Applications/NullPlayer.app/Contents/MacOS/NullPlayer \
  -uiMode audion -audionFacePath /absolute/path/to/face-folder
```

Do not redistribute a face unless its author allows it.
