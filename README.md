# Generic External API

Generic External API (GEAPI) is a SourceMod plugin which allows players to receive certain game events via a player-hosted API endpoint. The goal is to allow players to create arbitrary interactions with the game such as by activating an IoT device.

## Requirements

GEAPI requires SourceMod version >= 1.12 and the [Async Curl](https://github.com/bottiger1/sourcemod-async) plugin.

## Features

* Report player kills and deaths
  * Specifies if teamkill or killbind
* Report player assists
  * Specifies if teamkill assist
* Report map change

## API Documentation

The API uses a GET request with the `action` parameter to determine what type of information will be reported. The optional `secret` parameter can be used to prevent unwanted access. The `valid` parameter is always included at the end and set to 1 to guard against formatted string truncation.

The `version` parameter can be checked to prevent compatibility issues. This parameter refers to the API version, not the plugin version.

The API must always respond with an HTTP 200 OK status code, otherwise the response will be discarded. This currently only affects the challenge action.

### Actions 

`action=challenge`

This challenge requires a plain text response body of "GEAPI" to initialise the API to ensure the endpoint is intended for use with GEAPI. This action is always executed first to validate the API before it can be used.

`action=you_killed&teamkill=[0|1]`

Reports when the player achieves a kill.

The teamkill argument is 1 to indicate a teamkill, and 0 otherwise.

`action=you_died&teamkill=[0|1]&killbind=[0|1]`

Reports when the player is killed.

The teamkill argument is 1 to indicate a teamkill, and 0 otherwise.

The killbind argument is 1 to indicate a self-kill, and 0 otherwise.

`action=map_start`

Indicates that a new map has started.

## License

    GEAPI is a SourceMod plugin for API access.
    Copyright (C) 2025 A Foul Dev <a@foul.dev>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.