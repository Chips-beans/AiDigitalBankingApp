# Currency flag artwork

The user requested a borderless US flag and a Cambodia flag for KHR on
30 October 2026. These replace the padded US raster badge and riel glyph in the
transfer flow while retaining its 26 × 18 (22 × 15 receipt) design slots.

- `flag-us.svg`: [Wikimedia Commons, Flag of the United States](https://commons.wikimedia.org/wiki/File:Flag_of_the_United_States.svg),
  public-domain artwork, downloaded from the original SVG on 30 October 2026.
  This source uses Flutter-supported paths/uses instead of unsupported SVG markers.
- `flag-kh.svg`: [flag-icons](https://github.com/lipis/flag-icons),
  `flags/4x3/kh.svg` at revision `ac7e0eb3259eb62aa6100c435607e2fe03896a97`.
  The upstream MIT license is included as `flag-icons-LICENSE.txt`.

The originals are bundled locally. No border, white padding, outline container or
rounded badge is added by `TransferCurrencyFlag`. Flags are not tinted in dark mode.
