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
              extra argument WITHOUT EXTENSION. If episode artwork is included,
              it should have the same name as the MP3 file, be in JPEG format,
              and end in ".jpg". Notepad will be opened to write the episode
              description. It will be converted to HTML from Markdown.
  publish:    Finishes adding a new episode and publishes it immediately as the
              next episode. (Does not commit and push YET, you must do so.)
  delete:     Deletes an episode. If it was published, then regenerate is run as
              well. Files are moved to a ".trash" folder locally in case of
              accidental removal.
  regenerate: In case of template changes or unpublished changes to database,
              this regenerates every page (and feed).
  metadata:   Prints podcast metadata.
  schedule:   Schedules an episode to be published automatically. Requires
              "podcast.lua scheduler" running in the background. LuaDate is used
              to handle a variety of datetime formats automatically.
  scheduler:  Checks every minute for when an episode should be published, and
              publishes when necessary.
```

### Requirements
- ffprobe (part of ffmpeg)
- mp3tag (optional, to add episode artwork - primary reason for Windows requirement)
- notepad (if you don't have this, what did you *do*?)

## configuration.json
- `title`: Podcast title.
- `base_url`: Podcast URL. Must be already URL-escaped (if necessary), and must
  end in a `/`. (This is where the index page should be accessible.)
- `description`: Podcast description. Must be valid HTML.
- `timezone_offset`: Number. Local timezone offset, so that publication times
  are correct. (This script cannot handle DST.)
- `language`: String. A two-letter language identification code.
- `explicit`: true or false
- `categories`: An object analogous to the standard categories. Example:
  ```json
  {
    "categories": {
      "Technology": true,
      "Society & Culture": {
        "Personal Journals": true
      }
    }
  }
  ```
- `scheduled_episodes`: Object of UNIX timestamps and episode titles for
  automatic scheduling of episode publication.

- `episodes_data`: Episode metadata, addressed by episode title. Every episode has:
  - `title`: String.
  - `file_name`: String. **Excludes file extension.**
  - `duration_seconds`: Integer. Episode length/duration in seconds.
  - `urelencoded_title`: String. URL-encoded file name, **excluding extension**.
  - `summary`: String. HTML. Description of episode. Placed directly in feed and site.
  - `guid`: String. Generated UUIDv4 when `new` is called. (Must not change.)
  - `episode_number`: Integer. Only on published episodes.
  - `file_size`: Integer. Only on published episodes. File size in bytes.
  - `published_datetime`: String. Formatted as required for podcast publication.

- `episodes_list`: *Should* be an array, listing episodes in order by title. (In
  Lua, arrays/objects are interchangeable. If you ever delete an episode, this
  will turn into an object addressed by integers instead of being an array.)
- `next_episode_number`: Integer. To handle possibility of missing episodes.
