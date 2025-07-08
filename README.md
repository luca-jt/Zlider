# Zlider
A simple slide show program in Zig.

# How to use
- load a slide show file as a **command line** argument or **drag and drop** a file into the window
- toggle fullscreen with **F11**
- navigate the slides with the **arrow keys**
- dump the slides as PNG files with **I** (files are stored in the directory of the slide show file)
- unload the currently tracked/loaded slide show file with **C**

# Example
There is an example slide show file ``example/example.slides`` that explains the syntax that is used to create slide shows. Not all keywords of this "markup language" for the slide show files may occur in the example.\
Here is a complete list:

| Keyword | Semantics |
| :------ | :-------- |
| bg | Defines the background color of the slides with a hex value. |
| text_color | Defines the text color to be used with a hex value. |
| text_size | Defines the text size to be used. |
| line_spacing | Defines the line spacing factor to be used. |
| font | Changes the used font. Choices are: "serif", "monospace". |
| centered | Alignment specifier that centers all contents. |
| left | Alignment specifier that left-aligns all contents. |
| right | Alignment specifier that right-aligns all contents. |
| slide | Seperator between slides. |
| text | Marks the beginning and end of a text block. |
| space | Inserts a given amount of empty lines. |
| image | Inserts an image given by the path relative to the slide show file. |
| image_scale | Defines the image scaling factor to be used. |

## Hot reloading
Once there is an attempt to load a slide show file, it will be tracked and hot reloaded when the contents of the file change. This always happens, regardless of wether or not the slide show is parsed without errors. This way the editing process of the slide show files is easier - you can just keep the file loaded and immediately see the results.
