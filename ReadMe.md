# github.io-podcasts
A feed / site generator for using GitHub Pages (or compatible service) to publish a basic podcast.

Windows-only for the time being.

[Apple's Podcast Requirements](https://podcasters.apple.com/support/823-podcast-requirements)
is a good hub for learning about what is expected in podcast RSS feeds and such.  
Of particular importance is their list of [Podcast Categories](https://podcasters.apple.com/support/1691-apple-podcasts-categories).
- [A Podcaster’s Guide to RSS](https://help.apple.com/itc/podcasts_connect/#/itcb54353390) might be *even better*.
- [Artwork requirements](https://podcasters.apple.com/support/896-artwork-requirements) are not as strict as stated.
- [How to create an episode](https://podcasters.apple.com/support/825-how-to-create-an-episode) may be useful. New tag types have been added.

Useful tools:
- [Cast Feed Validator](https://www.castfeedvalidator.com)

## Usage
See `./podcast.lua -h` for help.

### Requirements
- ffprobe (part of ffmpeg)

Windows-only requirements:
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
- `next_episode_number`: Integer. To handle possibility of missing episodes.

## Episode Configurations
- `title`: String.
- `file_name`: String. **Excludes file extension.**
- `duration_seconds`: Integer. Episode length/duration in seconds.
- `urelencoded_file_name`: String. URL-encoded file name, **excluding extension**.
- `guid`: String. Generated UUIDv4 when `new` is called. (Must not change.)

- `episode_number`: Integer. Only on published episodes.
- `file_size`: Integer. Only on published episodes. File size in bytes.
- `published_datetime`: String. Only on published episodes. Formatted as required for podcast publication.

Summaries are kept in a Markdown file to be converted to HTML for placement in feed and website.
