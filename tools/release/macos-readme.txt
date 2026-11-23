Drag the game into Applications, then open it.

The game is not signed by Apple, so macOS stops it the first time ("cannot be opened" or "is damaged").
Either right-click (or Control-click) the game in Applications, choose Open, then Open again;
or, in Terminal, once:

    xattr -dr com.apple.quarantine "/Applications/<the game>.app"

To run setup again later (to add an extra or redo a step), in Terminal:

    open -a "<the game>" --args --setup

The game's data goes to ~/Library/Application Support/IAF (setup can choose another folder).
