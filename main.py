"""Launcher for hosts that only run a single file (Pterodactyl Python eggs: set the start file to main.py)."""
import sys

from voicekeeper.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
