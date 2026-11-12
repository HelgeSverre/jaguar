// vjag_test: the headless runner. It links without SDL.
module main

import os
import cli

fn main() {
	exit(cli.main_headless(os.args[1..]))
}
