/*
 * This file is part of Generic External API (GEAPI).
 * GEAPI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
 * GEAPI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 * You should have received a copy of the GNU General Public License along with GEAPI. If not, see <https://www.gnu.org/licenses/>.
 */

#pragma semicolon 1
#pragma newdecls required

#include <async>
#include <sourcemod>
#include <clientprefs>

#define URL_SIZE 64
#define URL_REQUEST_SIZE 1024
#define SECRET_SIZE 32
#define API_VERSION 1
#define CHALLENGE "GEAPI"

// TF2 supports 100 players, but SourceMod's MAXPLAYERS is still 65. Index 0 is the server.
#define _MAXPLAYERS 101

public Plugin myinfo =
{
    name = "Generic External API",
    author = "Foul Dev",
    description = "Call external player APIs in response to game events",
    version = "1.1",
    url = "https://github.com/FoulDev/geapi"
};

Cookie g_hApiUrl;
Cookie g_hApiSecret;
Cookie g_hApiEnabled;

char g_cApiUrls   [_MAXPLAYERS][URL_SIZE];    // Individual API URLs for each player
char g_cApiSecrets[_MAXPLAYERS][SECRET_SIZE]; // Optional secret to pass to the API
bool g_bApiValid  [_MAXPLAYERS];              // API passed initial check
bool g_bApiEnabled[_MAXPLAYERS];              // User has opted to enable the API
bool g_bApiChallengePending[_MAXPLAYERS];     // Prevent an unlikely race condition

public void OnPluginStart()
{
    g_hApiUrl     = new Cookie("geapi_url",     "Player API URL",    CookieAccess_Protected);
    g_hApiSecret  = new Cookie("geapi_secret",  "Player API Secret", CookieAccess_Protected);
    g_hApiEnabled = new Cookie("geapi_enabled", "Player API Toggle", CookieAccess_Protected);

    RegAdminCmd("sm_geapi_url",     Command_SetApiUrl,  ADMFLAG_GENERIC, "Full URL to API endpoint");
    RegAdminCmd("sm_geapi_secret",  Command_SetSecret,  ADMFLAG_GENERIC, "Optional secret");
    RegAdminCmd("sm_geapi_enabled", Command_SetEnabled, ADMFLAG_GENERIC, "Toggle API enabled");
    RegAdminCmd("sm_geapi_print",   Command_DebugPrint, ADMFLAG_GENERIC, "Print debug info");

    HookEvent("player_death", Event_PlayerDeath);

    LoadAllClientSettings();
}

public void OnMapStart()
{
    LoadAllClientSettings();

    for(int client = 1; client < MaxClients; client++)
    {
        if (ValidApiUser(client) == false) continue;

        Api_MapStart(client);
    }
}

public void OnClientConnected(int client)
{
    LoadClientSettings(client);
}

public void OnClientDisconnect(int client)
{
    UnloadClientSettings(client);
}

public void LoadAllClientSettings()
{
    for(int client = 1; client < MaxClients; client++)
    {
        if (IsClientInGame(client) == false) continue;
        LoadClientSettings(client);
    }
}

public void LoadClientSettings(int client)
{
    if (AreClientCookiesCached(client) == true)
    {
        g_hApiUrl   .Get(client, g_cApiUrls   [client], URL_SIZE);
        g_hApiSecret.Get(client, g_cApiSecrets[client], SECRET_SIZE);
        g_bApiEnabled[client] = g_hApiEnabled.GetInt(client, 0) > 0;
    }
    else
    {
        g_cApiUrls   [client] = "";
        g_cApiSecrets[client] = "";
        g_bApiEnabled[client] = false;
    }

    g_bApiValid[client] = false;

    if (strlen(g_cApiUrls[client]) > 0) 
        Api_Challenge(client);
}

public void UnloadClientSettings(int client)
{
    g_cApiUrls   [client] = "";
    g_cApiSecrets[client] = "";
    g_bApiValid  [client] = false;
    g_bApiEnabled[client] = false;
}

public void OnClientCookiesCached(int client)
{
    LoadClientSettings(client);
}

public Action Command_SetApiUrl(int client, int args)
{
    GetCmdArg(1, g_cApiUrls[client], URL_SIZE);

    if (strlen(g_cApiUrls[client]) > 0)
        Api_Challenge(client);

    return Plugin_Handled;
}

public Action Command_SetSecret(int client, int args)
{
    GetCmdArg(1, g_cApiSecrets[client], SECRET_SIZE);
    g_hApiSecret.Set(client, g_cApiSecrets[client]);

    return Plugin_Handled;
}

public Action Command_SetEnabled(int client, int args)
{
    g_bApiEnabled[client] = GetCmdArgInt(1) > 0;
    g_hApiEnabled.SetInt(client, g_bApiEnabled[client] ? 1 : 0);

    return Plugin_Handled;
}

public Action Command_DebugPrint(int client, int args)
{
    PrintToChat(client, "URL: %s",     g_cApiUrls   [client]);
    PrintToChat(client, "Secret: %s",  g_cApiSecrets[client]);
    PrintToChat(client, "Valid: %u",   g_bApiValid  [client]);
    PrintToChat(client, "Enabled: %u", g_bApiEnabled[client]);

    return Plugin_Handled;
}

public bool ValidApiUser(int client)
{
    return g_bApiValid[client] && g_bApiEnabled[client];
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim   = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int assister = GetClientOfUserId(event.GetInt("assister"));

    for(int client = 1; client < MaxClients; client++)
    {
        // Don't report to players not fully connected and joined to a team
        if (IsClientInGame(client) == false || IsClientObserver(client) == true) continue;
        if (ValidApiUser(client) == false) continue;

        bool killbind = victim == attacker;
        bool teamkill = killbind == false && attacker > 0 && GetClientTeam(victim) == GetClientTeam(attacker);
        bool teamkillAssist =                assister > 0 && GetClientTeam(victim) == GetClientTeam(assister);

        if (victim == client)
            Api_PlayerDied(client, teamkill, killbind);

        if (attacker == client && killbind == false)
            Api_PlayerKilled(client, teamkill);

        if (assister == client)
            Api_PlayerAssisted(client, teamkillAssist);
    }
}

public void Api_Challenge(int client)
{
    // Prevent a possible race condition
    if (g_bApiChallengePending[client] == true) return;

    char requestUrl[URL_REQUEST_SIZE];

    Format(requestUrl, sizeof(requestUrl),
        "%s?version=%u&secret=%s" ...
        "&action=challenge" ...
        "&valid=1",
        g_cApiUrls[client],
        API_VERSION,
        g_cApiSecrets[client]
    );

    g_bApiChallengePending[client] = true;
    Async_CurlGet(Async_CurlNew(GetClientUserId(client)), requestUrl, OnChallengeResponse);
}

public void OnChallengeResponse(CurlHandle request, int curlcode, int httpcode, int size, int clientid)
{
    bool valid = false;
    int client = GetClientOfUserId(clientid);

    if (client > 0 && curlcode == 0 && httpcode == 200 && size >= 5)
    {
        char buffer[5];
        Async_CurlGetData(request, buffer, 5);

        if (StrEqual(buffer, CHALLENGE) == true)
        {
            valid = true;
            g_hApiUrl.Set(client, g_cApiUrls[client]);
        }
    }

    g_bApiValid[client] = valid;
    g_bApiChallengePending[client] = false;
    Async_Close(request);
}

public void Api_PlayerDied(int client, bool teamkill, bool killbind)
{
    char requestUrl[URL_REQUEST_SIZE];

    Format(requestUrl, sizeof(requestUrl),
        "%s?version=%u&secret=%s" ...
        "&action=you_died" ...
        "&teamkill=%u" ...
        "&killbind=%u" ...
        "&valid=1",
        g_cApiUrls[client],
        API_VERSION,
        g_cApiSecrets[client],
        teamkill,
        killbind
    );

    Async_CurlGet(Async_CurlNew(), requestUrl, OnRequestDone);
}

public void Api_PlayerKilled(int client, bool teamkill)
{
    char requestUrl[URL_REQUEST_SIZE];

    Format(requestUrl, sizeof(requestUrl),
        "%s?version=%u&secret=%s" ...
        "&action=you_killed" ...
        "&teamkill=%u" ...
        "&valid=1",
        g_cApiUrls[client],
        API_VERSION,
        g_cApiSecrets[client],
        teamkill
    );

    Async_CurlGet(Async_CurlNew(), requestUrl, OnRequestDone);
}

public void Api_PlayerAssisted(int client, bool teamkill)
{
    char requestUrl[URL_REQUEST_SIZE];

    Format(requestUrl, sizeof(requestUrl),
        "%s?version=%u&secret=%s" ...
        "&action=you_assisted" ...
        "&teamkill=%u" ...
        "&valid=1",
        g_cApiUrls[client],
        API_VERSION,
        g_cApiSecrets[client],
        teamkill
    );

    Async_CurlGet(Async_CurlNew(), requestUrl, OnRequestDone);
}

public void Api_MapStart(int client)
{
    char requestUrl[URL_REQUEST_SIZE];

    Format(requestUrl, sizeof(requestUrl),
        "%s?version=%u&secret=%s" ...
        "&action=map_start" ...
        "&valid=1",
        g_cApiUrls[client],
        API_VERSION,
        g_cApiSecrets[client]
    );

    Async_CurlGet(Async_CurlNew(), requestUrl, OnRequestDone);
}

public void OnRequestDone(CurlHandle request, int curlcode, int httpcode, int size, int userdata)
{
    Async_Close(request);
}