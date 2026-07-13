import AppKit

/// The Claude logo shown next to the progress bars in the menu bar icon.
///
/// Menu bar icons need to be self-contained bitmaps baked into the binary —
/// there's no reliable "resources folder next to the executable" once this
/// gets repackaged into a hand-built `.app` bundle (see `build_app.sh`), so
/// the PNG is embedded as base64 rather than loaded from a file at runtime.
enum ClaudeLogo {
    /// Set via base64-encoding the user-supplied PNG. Falls back to a system
    /// symbol placeholder in `MenuBarProgressIcon` while this is empty.
    private static let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAAHhlWElmTU0AKgAAAAgABAEaAAUAAAABAAAAPgEbAAUAAAABAAAARgEoAAMAAAABAAIAAIdpAAQAAAABAAAATgAAAAAAAABIAAAAAQAAAEgAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAECgAwAEAAAAAQAAAEAAAAAAdd52hwAAAAlwSFlzAAALEwAACxMBAJqcGAAABNJJREFUeAHtWt1rXEUUn497dzcGoU+iIvgiaTUqlNYKPor66geYiPokNC+CL4oJBnwQKonQP8A860Oi9A9Q8U3B2iJaqk0QqiBCi0pa7SZ779wZf+cms727m72zd29vvnaGbObunJlzfvObYc6Zc5cxXzwDngHPgGfAM+AZ8Ax4BjwDngHPwAgywF1zXpubeiaU4UOtOHZ13VfyehiyOIl/nVhY+SoPWJAnJJnR7M3xMfmCdFLl0rS78kYo2XpTnYPVcgQwxlsbsWKbcbK7MyhpzTAD6LzlUiNcHQ673BNw2FfYNb+R3wFOL+BiMJSCCX7bRURJwgzOnyoKmalJ2VatYShOdPv7MA+lCKBpK20uGqPXyTjmTTvqFAgZN3eYBY7ZY8K3NlVyHnbTWaPtCJ5PlOG7FAFCcBZr9tbDi8vfEgFUrsxNXwoEfzROysDa0pX9D50s0ubqsYXlp237L7OvPBUK/k2ih7dV+gwQgrX35IWZmZAbRhujkkK6yYZVnrVt24rWpQkoanC/9fcE7LcV2W08fgcMwHjuEasFa9+STix9rAwnb1hNId1kw2rP2rZtHXV6I+po6fnCV2env+5p7Wgwk4KLeyjo6C7bx/0PkKzjw+H/Ofz/SVSVxAHQfQu6LwALuGD0OQJMx3uRISBJ4wZ9HbAuo9821O4ZQPDb/Ks7jW/3pEhrp8nbDtlIkBTFFUeCISJBOxvClRcJEgmEL68ELdXewXn9+sryAPQdNKSANmFUAC8R5JpfPj1DAj1IwzwBB2m1qsA68jsgGEP2NK9E8AJlblt5uquWSdwgay4vsKGS07lADJuBK3liN0/7XDwDCsn9AfP3GyZZyhtiXWrfPmvvTn9Sr8nXDlpanN4LtKLk04mPll/vOzkInGcAXG+ppEme8aplg2B3ElA1yL3W7wnY6xXYa/sjvwPcBxw3tUaAWIGueigUF2Rvh+RncUVNb2jUheTZlHgNY8nVON0NKc8U0pXqy1x+yE5qb1tGdsieLXT7s36fMG/GqmZl/WonAXg9fnYj0p9HWm1RYPg8fOwkxQVkEAA+4Npcodyw0SJgXH8ohXiASMKfimI1xwX7k91OHvfD0tWOFyya3Q92F2AGWXGOgEz/0YrZe1xoRWkYI/gxtL9Ptsjvq0RfbiXqDClCxoBj/O9dSnu+Fl0YtjY79UUtCJ6layZFWolInjx65rPzVvPq7NRPuLM/pjTtBPCj4olHzp5zArHjs/XPb7/0oAzCNVrYADlw5BouHV1cedz2WZ1/+ZTU8juKVOtY8UipLycWV56z8kHqwmcAtkFn7Kxl3RraytljvTNFSNnIfC302DuWi+x7AZaxTYp7sA1grQPsAP0PXRdPwKFb0oITKrwD4PDwTpSnHmD7ZO4+SNtyYCmsfwf8ffXBK1Amuo2FsO0wPrfJ6QZ7RhtzE25nnVwPR2I6FLL793M3UjlOZgCKEgN3MGTRGBtw+Y/WpqbxZhTlRlYV2YaZFAvhgdu5mZUP8lyYgEQ23hBhVDcxfBNegf97V/KXNXRyaSn+8Z0Xnx8bqwdRc2tjXBv/G7n54QrGXr2vee9xCqOCGmz9FymyYbVFdXXx7qacbEIuQkrcNJy/CrNjfe0Z8Ax4BjwDngHPgGfAMzDqDPwPzPa/oFZT2iEAAAAASUVORK5CYII="

    static var image: NSImage? {
        guard !base64PNG.isEmpty, let data = Data(base64Encoded: base64PNG) else { return nil }
        return NSImage(data: data)
    }
}
