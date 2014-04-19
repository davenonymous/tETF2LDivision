#pragma semicolon 1
#include <sourcemod>
#include <tDownloadCache>
#include <smlib>
#include <regex>
#include <kvizzle>

#define VERSION 		"0.1.0"

new Handle:g_hCvarEnabled = INVALID_HANDLE;
new Handle:g_hCvarAnnounce = INVALID_HANDLE;
new Handle:g_hCvarAnnAdminOnly = INVALID_HANDLE;
new Handle:g_hCvarShowHighlander = INVALID_HANDLE;
new Handle:g_hCvarMaxAge = INVALID_HANDLE;

new bool:g_bEnabled;
new bool:g_bAnnounce;
new bool:g_bAnnounceAdminOnly;
new bool:g_bShowHighlander;
new g_iMaxAge = 7 * (24 * 60 * 60);

new Handle:g_hRegExSeason;

new Handle:g_hPlayerData[MAXPLAYERS+1];

public Plugin:myinfo = {
	name 		= "tETF2LDivision",
	author 		= "Thrawn",
	description = "Shows a players ETF2L team and division.",
	version 	= VERSION,
};

public OnPluginStart() {
	CreateConVar("sm_tetf2ldivision_version", VERSION, "", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	// Create some convars
	g_hCvarEnabled = CreateConVar("sm_tetf2ldivision_enable", "1", "Enable tETF2LDivision.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarShowHighlander = CreateConVar("sm_tetf2ldivision_highlander", "0", "Show the highlander instead of the 6on6 team.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarAnnounce = CreateConVar("sm_tetf2ldivision_announce", "1", "Announce players on connect.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarAnnAdminOnly = CreateConVar("sm_tetf2ldivision_announce_adminsonly", "0", "Announce players on connect to admins only.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarMaxAge = CreateConVar("sm_tetf2ldivision_maxage", "7", "Update infos about all players every x-th day.", FCVAR_PLUGIN, true, 1.0, true, 31.0);
	HookConVarChange(g_hCvarEnabled, Cvar_Changed);
	HookConVarChange(g_hCvarAnnounce, Cvar_Changed);
	HookConVarChange(g_hCvarAnnAdminOnly, Cvar_Changed);
	HookConVarChange(g_hCvarShowHighlander, Cvar_Changed);
	HookConVarChange(g_hCvarMaxAge, Cvar_Changed);


	// Match season information by regex. Overkill, but eaaase.
	g_hRegExSeason = CompileRegex("Season (\\d\\d)");

	// Create the cache directory if it does not exist
	new String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/etf2lcache/");

	if(!DirExists(sPath)) {
		CreateDirectory(sPath, 493);
	}


	// Account for late loading
	// - This triggers announcements. But that shouldn't be a big deal,
	//   so we don't handle it and overcomplicate things by doing so.
	for(new iClient = 1; iClient <= MaxClients; iClient++) {
		if(IsClientInGame(iClient) && !IsFakeClient(iClient)) {
			new String:sAuthId[32];
			GetClientAuthString(iClient, sAuthId, sizeof(sAuthId));
			UpdateClientData(iClient, sAuthId);
		}
	}

	// Provide a command for clients
	RegConsoleCmd("sm_div", Command_ShowDivisions);
	RegConsoleCmd("sm_divdetail", Command_ShowPlayerDetail);
}

public OnConfigsExecuted() {
	g_bEnabled = GetConVarBool(g_hCvarEnabled);
	g_bAnnounce = GetConVarBool(g_hCvarAnnounce);
	g_bAnnounceAdminOnly = GetConVarBool(g_hCvarAnnAdminOnly);
	g_bShowHighlander = GetConVarBool(g_hCvarShowHighlander);
	g_iMaxAge = GetConVarInt(g_hCvarMaxAge) * (24 * 60 * 60);
}

public Cvar_Changed(Handle:convar, const String:oldValue[], const String:newValue[]) {
	OnConfigsExecuted();

	// Reload data if plugin got enabled or the team-mode got switched
	if((convar == g_hCvarEnabled && g_bEnabled) || convar == g_hCvarShowHighlander) {
		for(new iClient = 1; iClient <= MaxClients; iClient++) {
			if(IsClientInGame(iClient) && !IsFakeClient(iClient)) {
				new String:sAuthId[32];
				GetClientAuthString(iClient, sAuthId, sizeof(sAuthId));
				UpdateClientData(iClient, sAuthId);
			}
		}
	}
}

public Action:Command_ShowPlayerDetail(client, args) {
	if(!g_bEnabled) {
		ReplyToCommand(client, "tDivisions is disabled.");
		return Plugin_Handled;
	}

	if(args == 0 || args > 1) {
		ReplyToCommand(client, "No target specified. Usage: sm_divdetail <playername>");
		return Plugin_Handled;
	}

	decl String:strTarget[32]; GetCmdArg(1, strTarget, sizeof(strTarget));

	// Process the targets
	decl String:strTargetName[MAX_TARGET_LENGTH];
	decl TargetList[MAXPLAYERS], TargetCount;
	decl bool:TargetTranslate;

	if ((TargetCount = ProcessTargetString(strTarget, client, TargetList, MAXPLAYERS, COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_MULTI,
										   strTargetName, sizeof(strTargetName), TargetTranslate)) <= 0) {
		return Plugin_Handled;
	}

	// Apply to all targets (this can only be one, but anyway...)
	for (new i = 0; i < TargetCount; i++) {
		new iClient = TargetList[i];

		new String:sPlayerId[12];
		GetTrieString(g_hPlayerData[iClient], "PlayerId", sPlayerId, sizeof(sPlayerId));

		if(strlen(sPlayerId) <= 0) {
			ReplyToCommand(client, "Sorry. The ETF2L user-id is unknown for '%s'", strTarget);
			return Plugin_Handled;
		}

		new String:sURL[128];
		Format(sURL, sizeof(sURL), "http://etf2l.org/forum/user/%s/", sPlayerId);

		ShowMOTDPanel(client, "ETF2L Profile", sURL, MOTDPANEL_TYPE_URL);
	}

	return Plugin_Handled;


}

public Action:Command_ShowDivisions(client, args) {
	if(!g_bEnabled) {
		ReplyToCommand(client, "tDivisions is disabled.");
		return Plugin_Handled;
	}

	if(args == 0) {
		for (new iClient=1; iClient<=MaxClients;iClient++) {
			if (IsClientInGame(iClient) && !IsFakeClient(iClient) && g_hPlayerData[iClient] != INVALID_HANDLE) {
				new String:msg[253];
				GetAnnounceString(iClient, msg, sizeof(msg));

				Color_ChatSetSubject(iClient);
				Client_PrintToChat(client, false, msg);
			}
		}
	}

	if(args == 1) {
		decl String:strTarget[32]; GetCmdArg(1, strTarget, sizeof(strTarget));

		// Process the targets
		decl String:strTargetName[MAX_TARGET_LENGTH];
		decl TargetList[MAXPLAYERS], TargetCount;
		decl bool:TargetTranslate;

		if ((TargetCount = ProcessTargetString(strTarget, client, TargetList, MAXPLAYERS, COMMAND_FILTER_CONNECTED,
											   strTargetName, sizeof(strTargetName), TargetTranslate)) <= 0)
		{
			return Plugin_Handled;
		}

		// Apply to all targets
		for (new i = 0; i < TargetCount; i++) {
			new iClient = TargetList[i];
			if (IsClientInGame(iClient) && !IsFakeClient(iClient) && g_hPlayerData[iClient] != INVALID_HANDLE) {
				new String:msg[253];
				GetAnnounceString(iClient, msg, sizeof(msg));

				Color_ChatSetSubject(iClient);
				Client_PrintToChat(client, false, msg);
			}
		}
	}

	return Plugin_Handled;
}


public OnClientAuthorized(iClient, const String:auth[]) {
	if(g_bEnabled) {
		UpdateClientData(iClient, auth);
	}
}

public OnClientDisconnect(iClient) {
	if(g_hPlayerData[iClient] != INVALID_HANDLE) {
		CloseHandle(g_hPlayerData[iClient]);
		g_hPlayerData[iClient] = INVALID_HANDLE;
	}
}

public UpdateClientData(iClient, const String:auth[]) {
	if(IsFakeClient(iClient))return;

	// This is probably not necessery anymore, just use the id directly?
	new String:sFriendId[64];
	AuthIDToFriendID(auth, sFriendId, sizeof(sFriendId));

	new String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/etf2lcache/%s.vdf", sFriendId);

	new String:sWebPath[255];
	Format(sWebPath, sizeof(sWebPath), "/player/%s/full.vdf", auth);

	DC_UpdateFile(sPath, "api.etf2l.org", 80, sWebPath, g_iMaxAge, OnEtf2lDataReady, iClient);
}

public OnEtf2lDataReady(bool:bSuccess, Handle:hSocketData, any:iClient) {
	if(!bSuccess)return;

	new String:sPath[PLATFORM_MAX_PATH];
	GetTrieString(hSocketData, "path", sPath, sizeof(sPath));

	if(g_hPlayerData[iClient] != INVALID_HANDLE) {
		CloseHandle(g_hPlayerData[iClient]);
		g_hPlayerData[iClient] = INVALID_HANDLE;
	}

	g_hPlayerData[iClient] = ReadPlayer(iClient, sPath);

	if(g_bAnnounce && g_hPlayerData[iClient] != INVALID_HANDLE) {
		AnnouncePlayerToAll(iClient);
	}
}


public GetAnnounceString(iClient, String:msg[], maxlen) {
	Format(msg, maxlen, "{T}%N{N}", iClient);

	if(g_hPlayerData[iClient] != INVALID_HANDLE) {
		new String:sSteamId[32];
		new String:sDisplayName[255];
		new String:sTeamName[255];
		new String:sDivision[32];
		new String:sEvent[255];

		GetTrieString(g_hPlayerData[iClient], "SteamId", sSteamId, sizeof(sSteamId));
		GetTrieString(g_hPlayerData[iClient], "DisplayName", sDisplayName, sizeof(sDisplayName));

		if(g_bShowHighlander) {
			GetTrieString(g_hPlayerData[iClient], "9v9TeamName", sTeamName, sizeof(sTeamName));
			GetTrieString(g_hPlayerData[iClient], "9v9Division", sDivision, sizeof(sDivision));
			GetTrieString(g_hPlayerData[iClient], "9v9Event", sEvent, sizeof(sEvent));
		} else {
			GetTrieString(g_hPlayerData[iClient], "6v6TeamName", sTeamName, sizeof(sTeamName));
			GetTrieString(g_hPlayerData[iClient], "6v6Division", sDivision, sizeof(sDivision));
			GetTrieString(g_hPlayerData[iClient], "6v6Event", sEvent, sizeof(sEvent));
		}


		//Player is registered
		Format(msg, maxlen, "%s {N}(%s){N}", msg, sDisplayName);

		if(strlen(sTeamName) > 0) {
			//Player has a 6on6 Team
			Format(msg, maxlen, "%s, {OG}%s{N}", msg, sTeamName);

			if(strlen(sDivision) > 0) {
				Format(msg, maxlen, "%s, {OG}%s{N}, %s", msg, sEvent, sDivision);
			} else {
				StrCat(msg, maxlen, ", inactive");
			}

		} else {
			StrCat(msg, maxlen, ", no team");
		}
	} else {
		StrCat(msg, maxlen, ", unregistered");
	}

	return;
}

public AnnouncePlayerToAll(iClient) {
	new String:msg[253];
	GetAnnounceString(iClient, msg, sizeof(msg));

	for (new i=1; i<=MaxClients;i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			if(g_bAnnounceAdminOnly && GetUserAdmin(i) == INVALID_ADMIN_ID)
				continue;

			Color_ChatSetSubject(iClient);
			Client_PrintToChat(i, false, msg);
		}
	}
}

public Handle:ReadPlayer(iClient, String:sPath[]) {
	new Handle:hKV = KvizCreateFromFile("response", sPath);
	if(hKV == INVALID_HANDLE) {
		LogError("Could not parse keyvalues file '%s' for %N", sPath, iClient);
		return INVALID_HANDLE;
	}

	new iETF2LId = KvizGetNum(hKV, -1, "player.id");
	if(iETF2LId == -1) {
		LogError("Player '%N' is not registered at ETF2L.", iClient);
		KvizClose(hKV);
		return INVALID_HANDLE;
	}

	new String:sSteamId[32];
	new String:sDisplayName[255];
	new String:sSixTeamName[255];
	new String:sSixDivision[32];
	new String:sSixEvent[255];
	new String:sNineTeamName[255];
	new String:sNineDivision[32];
	new String:sNineEvent[255];

	// Grab Player Details
	KvizGetString(hKV, sDisplayName, sizeof(sDisplayName), "", "player.name");
	KvizGetString(hKV, sSteamId, sizeof(sSteamId), "", "player.steam.id");


	// Find the highlander team
	KvizJumpToKey(hKV, false, "player.teams:any-child.type:has-value(Highlander):parent");
	// ... and grab the name
	KvizGetString(hKV, sNineTeamName, sizeof(sNineTeamName), "", "name");

	// Find the latest competition that team has participated ...
	KvizJumpToKey(hKV, false, "competitions:last-child");
	// ... and grab some details
	KvizGetString(hKV, sNineDivision, sizeof(sNineDivision), "", "division.name");
	new iNineTier = KvizGetNum(hKV, -1, "division.tier");
	KvizGetString(hKV, sNineEvent, sizeof(sNineEvent), "", "competition");
	KvizGoBack(hKV);


	// Find the 6v6 team
	KvizJumpToKey(hKV, false, "player.teams:any-child.type:has-value(6on6):parent");
	// ... and grab the name
	KvizGetString(hKV, sSixTeamName, sizeof(sSixTeamName), "", "name");

	// Find the latest competition that team has participated ...
	KvizJumpToKey(hKV, false, "competitions:last-child");
	// ... and grab some details
	KvizGetString(hKV, sSixDivision, sizeof(sSixDivision), "", "division.name");
	new iSixTier = KvizGetNum(hKV, -1, "division.tier");
	KvizGetString(hKV, sSixEvent, sizeof(sSixEvent), "", "competition");


	// Close the file
	KvizGoBack(hKV);
	KvizClose(hKV);

	// Post-Processing: Strip the event name
	if(MatchRegex(g_hRegExSeason, sSixEvent) > 0) {
		new String:sYear[4];
		GetRegexSubString(g_hRegExSeason, 1, sYear, sizeof(sYear));

		Format(sSixEvent, sizeof(sSixEvent), "Season %s", sYear);
	}

	if(MatchRegex(g_hRegExSeason, sNineEvent) > 0) {
		new String:sYear[4];
		GetRegexSubString(g_hRegExSeason, 1, sYear, sizeof(sYear));

		Format(sNineEvent, sizeof(sNineEvent), "Season %s", sYear);
	}

	// Encapsulate in a Trie and return
	new Handle:hResult = CreateTrie();
	SetTrieString(hResult, "SteamId", sSteamId);
	SetTrieString(hResult, "DisplayName", sDisplayName);

	SetTrieString(hResult, "6v6TeamName", sSixTeamName);
	SetTrieString(hResult, "6v6Division", sSixDivision);
	SetTrieString(hResult, "6v6Event", sSixEvent);
	SetTrieValue(hResult,  "6v6DivisionTier", iSixTier);

	SetTrieString(hResult, "9v9TeamName", sNineTeamName);
	SetTrieString(hResult, "9v9Division", sNineDivision);
	SetTrieString(hResult, "9v9Event", sNineEvent);
	SetTrieValue(hResult,  "9v9DivisionTier", iNineTier);

	SetTrieValue(hResult, "PlayerId", iETF2LId);


	return hResult;
}


AuthIDToFriendID(const String:AuthID[], String:FriendID[], size) {
	decl String:sAuthId[32];
	strcopy(sAuthId, sizeof(sAuthId), AuthID);

	ReplaceString(sAuthId, strlen(sAuthId), "STEAM_", "");

	if (StrEqual(sAuthId, "ID_LAN")) {
		FriendID[0] = '\0';

		return;
	}

	decl String:toks[3][16];

	ExplodeString(sAuthId, ":", toks, sizeof(toks), sizeof(toks[]));

	//new unknown = StringToInt(toks[0]);
	new iServer = StringToInt(toks[1]);
	new iAuthID = StringToInt(toks[2]);

	new iFriendID = (iAuthID*2) + 60265728 + iServer;

	Format(FriendID, size, "765611979%d", iFriendID);
}