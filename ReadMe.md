# github.io-podcasts
A feed / site generator for using GitHub Pages (or compatible service) to publish a basic podcast.

Windows-only for the time being.

[Apple's Podcast Requirements](https://podcasters.apple.com/support/823-podcast-requirements)
is a good hub for learning about what is expected in podcast RSS feeds and such.  
Of particular importance is their list of [Podcast Categories](https://podcasters.apple.com/support/1691-apple-podcasts-categories).

Useful tools:
- [Cast Feed Validator](https://www.castfeedvalidator.com)

## Usage
```
Usage:

  podcast.lua <action> <title> [options]

<action>:
  new:        Starts the process of adding a new episode. An MP3 file should be
              placed in the root of the repo, next to this script. The file name
              should match the title. If it doesn't, specify the file name as an
              extra argument. If episode artwork is included, it should have the
              same name as the MP3 file, be in JPEG format, and end in ".jpg".
              Notepad will be opened to write the episode description. It will
              be converted to HTML from Markdown.
  publish:    Finishes adding a new episode and publishes it immediately as the
              next episode. (Does not commit and push YET, you must do so.)
  delete:     Deletes an episode. If it was published, then regenerate is run as
              well. Files are moved to a ".trash" folder locally in case of
              accidental removal.
  regenerate: In case of template changes or unpublished changes to database,
              this regenerates every page (and feed).
```

### Requirements
- ffprobe (part of ffmpeg)
- mp3tag (optional, to add episode artwork - primary reason for Windows requirement)
- notepad (if you don't have this, what did you *do*?)

## configuration.json
- `base_url` must be already URL-escaped (if necessary), and must end in a `/`.  
- `description` must be valid HTML.
