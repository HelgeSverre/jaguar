module loader

// ErrorCode classifies every way `plan` can refuse an image, so callers can
// match on the cause instead of parsing messages.
pub enum ErrorCode {
	too_small                // fewer bytes than the smallest header or instruction
	too_large                // does not fit the 6 MiB cartridge window or main RAM
	truncated                // a header or a declared payload runs past the end of the file
	bad_header               // recognized format whose header fields are inconsistent
	bad_range                // a destination or the entry lies outside RAM and the cartridge window
	overlap                  // two load regions cover the same guest address
	odd_entry                // the 68000 cannot start at an odd address
	unsupported_variant      // recognized container, variant not specified well enough to load
	unresolved_relocations   // object file or relocatable program, not an absolute executable
	blank_image              // every byte is identical (an erased or failed dump)
	bad_option               // an explicit option does not apply to the image
	ambiguous_needs_override // nothing identifies the image; explicit options are required
}

// LoadError is the only error type `plan` returns.
pub struct LoadError {
	Error
pub:
	code    ErrorCode // machine-matchable cause
	message string    // human explanation with the offending values
}

// msg renders the error as `<code>: <message>`.
pub fn (err LoadError) msg() string {
	return '${err.code}: ${err.message}'
}

// fail builds a LoadError as an IError, ready to `return`.
fn fail(code ErrorCode, message string) IError {
	return LoadError{
		code:    code
		message: message
	}
}
