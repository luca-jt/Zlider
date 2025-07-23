<div align="center">
    <img src="src/baked/readme_title.png" width=50% height=50% alt="Zlider" />
</div>

___

A simple slide show program in Zig.

# How to use
- load a slide show file as a **command line** argument or **drag and drop** a file into the window
- toggle fullscreen with **F11** (there are some issues with choosing the correct monitor on linux wayland as it does not expose the window position)
- navigate the slides with the **arrow keys**
- dump the slides as PNG files with **I** (files are stored in the directory of the slide show file)
- dump the slides as a PDF file with **P** (file is stored in the directory of the slide show file)
- press **Ctrl-...** when dumping to compress fallthrough animation slides
- unload the currently tracked/loaded slide show file with **C**

# Example
There is an example slide show file ``example/example.slides`` that explains the syntax that is used to create slide shows. Not all keywords of this "markup language" for the slide show files may occur in the example.\
Here is a complete list:

| Keyword | Input Literal Type | Semantics |
| :------ | :---- | :-------- |
| aspect_ratio | ``Integer`` ``Integer`` | Defines the aspect ratio of all the slides in a slide show by a fraction. |
| black_bars | ``Boolean`` | Flag to enable or disable black bars on the edges of the slides if aspect ratios don't match. |
| layer | ``Integer`` | Changes the depth layer data is added to. 0 is the top layer and 9 the bottom layer. |
| bg | ``32bit Hex`` | Defines the background color of the slides with a hex value. |
| text_color | ``32bit Hex`` | Defines the text color to be used with a hex value. |
| text_size | ``Integer`` | Defines the text size to be used. |
| line_spacing | ``Float`` | Defines the line spacing factor to be used. |
| font | "serif", "sans_serif", "monospace" | Changes the used font. |
| center | - | Alignment specifier that centers all contents. |
| left | - | Alignment specifier that left-aligns all contents. |
| right | - | Alignment specifier that right-aligns all contents. |
| slide | ("fallthrough") | Seperator between slides. |
| text | ``String`` text | Marks the beginning and end of a text block. |
| space | ``Integer`` | Inserts a given amount of empty lines. |
| image | ``String`` (``Float``) (``Float``) | Inserts an image given by the path relative to the slide show file with an optional scale and optional rotation angle in degrees. |
| header | - | Defines a header for all slides at the end of the file. |
| footer | - | Defines a footer for all slides at the end of the file. |
| no_header | - | Excludes the header from the current slide. |
| no_footer | - | Excludes the footer from the current slide. |
| quad | ``32bit Hex`` ``Float`` ``Float`` | Defines a quad with a color, width and height. |
| left_space | ``Float`` | Defines the space left on the left side of the slide in pixels. |
| right_space | ``Float`` | Defines the space left on the right side of the slide in pixels. |
| template | - | Defines a slide background layer at the end of the file that is added to every slide. |
| no_template | - | Excludes the template from a slide. |

``()`` specify optional parameters. ``""`` specify exact names.

## Hot reloading
Once there is an attempt to load a slide show file, it will be tracked and hot reloaded when the contents of the file change. This always happens, regardless of wether or not the slide show is parsed without errors. This way the editing process of the slide show files is easier - you can just keep the file loaded and immediately see the results. If you unload the slide show, the file will no longer be tracked.

## Targets
- Linux
- Windows
- MacOS (untested)

This is made possible because the project already ships most external dependency files such that you don't have to get them yourself. There are also some custom modifications that are possible because of that.

> [!Warning]
> Support for MacOS in theory is there, but it's not tested at all. Other targets might require some work, too. PR's are welcome.

## Planned Features
- Conversion to PDF files bakes actual text data and not just rendered images.
