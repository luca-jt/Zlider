# Zlider
A simple slide show program in Zig.

# How to use
- load a slide show file as a command line argument or drag and drop a file into the window
- toggle fullscreen with F11
- navigate the slides with the arrow keys
- dump the slides as PNG files with I
- unload the currently tracked/loaded slide show file with C

# Example
There is an example slide show file ``example/example.slides`` that explains the syntax that is used to create slide shows.

## Hot reloading
Once there is an attempt to load a slide show file, it will be tracked and hot reloaded when the contents of the file change. This always happens, regardless of wether or not the slide show is parsed without errors. This way the editing process of the slide show files is easier - you can just keep the file loaded and immediately see the results.
