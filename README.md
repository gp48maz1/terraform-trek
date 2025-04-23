# terraform-trek
A rouge-like game built in Lua and Love2d inspired by Terraform Mars

## Running Locally

To run Terraform Trek on your local machine using LÖVE, follow these steps:

### 1. Find Your LÖVE Installation Path

You need to know the path to the LÖVE executable.

*   **macOS:**
    *   If installed in the standard Applications folder, the path to the executable is typically `/Applications/love.app/Contents/MacOS/love`.
    *   You can verify this by right-clicking `love.app` in Finder, selecting "Show Package Contents", and navigating to `Contents/MacOS/`.
*   **Windows:**
    *   The path is usually something like `C:\Program Files\LOVE\love.exe` or `C:\Program Files (x86)\LOVE\love.exe`.
    *   Find where you installed LÖVE and locate `love.exe`.

### 2. Set Up the Launch Script

A script is provided to easily launch the game.

*   **macOS:**
    1.  Make sure the path in `run_local.sh` matches your LÖVE installation path found in step 1. If it's different, edit the last line of the script.
    2.  Open your terminal, navigate to the `terraform-trek` project directory.
    3.  Make the script executable by running: `chmod +x run_local.sh`
    4.  Run the game using: `./run_local.sh`

*   **Windows:**
    1.  Create a file named `run_local.bat` in the `terraform-trek` project directory.
    2.  Add the following content, **replacing `"C:\Program Files\LOVE\love.exe"` with your actual LÖVE path** found in step 1:
        ```batch
        @echo off
        REM Replace the path below with your actual love.exe path
        "C:\Program Files\LOVE\love.exe" .
        pause
        ```
    3.  Save the file.
    4.  Double-click `run_local.bat` to start the game. The `pause` command keeps the console window open if errors occur.
