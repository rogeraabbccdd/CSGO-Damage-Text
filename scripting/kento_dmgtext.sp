#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <kento_csgocolors>

#pragma newdecls required

bool text_show[MAXPLAYERS + 1];
char text_size[MAXPLAYERS + 1][64];
char text_color_normal[MAXPLAYERS + 1][64];
char text_color_kill[MAXPLAYERS + 1][64];
int SayingSettings[MAXPLAYERS + 1];

ConVar Cvar_TableName;
char Table_Name[200];

Database ddb = null;

public Plugin myinfo =
{
	name = "[CS:GO] Damage Text",
	author = "Kento",
	version = "1.0",
	description = "Show damage text like RPG games :D",
	url = "http://steamcommunity.com/id/kentomatoryoshika/"
};

public void OnPluginStart() 
{
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	
	RegConsoleCmd("sm_dmgtext", Command_DmgText, "Damage Text Settings");
	RegConsoleCmd("say", Command_Say);
	
	LoadTranslations("kento.dmgtext.phrases");
	
	Cvar_TableName = CreateConVar("sm_dmgtext_table", "dmgtext", "MySQL table name to save dmg text settings.");
}

public void OnClientPutInServer(int client)
{
	if(IsValidClient(client) && !IsFakeClient(client))
	{
		LoadClientSettings(client);
	}
}

public void OnConfigsExecuted()
{
	Cvar_TableName.GetString(Table_Name, sizeof(Table_Name));
	
	if (SQL_CheckConfig("dmgtext"))
	{
		SQL_TConnect(OnSQLConnect, "dmgtext");
	}
	else if (!SQL_CheckConfig("dmgtext"))
	{
		SetFailState("Can't find an entry in your databases.cfg with the name \"dmgtext\".");
		return;
	}
}

public void OnSQLConnect(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
	{
		SetFailState("(OnSQLConnect) Can't connect to mysql");
		return;
	}
	
	ddb = view_as<Database>(CloneHandle(hndl));
	
	CreateTable();
}

void CreateTable()
{
	char sQuery[1024];
	Format(sQuery, sizeof(sQuery), 
	"CREATE TABLE IF NOT EXISTS `%s`  \
	( id INT NOT NULL AUTO_INCREMENT ,  \
	steamid VARCHAR(64) NOT NULL ,  \
	showtext INT NOT NULL ,  \
	textsize INT NOT NULL ,  \
	normal_color VARCHAR(64) NOT NULL ,  \
	kill_color VARCHAR(64) NOT NULL ,  \
	PRIMARY KEY (id))  \
	ENGINE = InnoDB;", Table_Name);
	
	ddb.Query(SQL_CreateTable, sQuery);
}

public void SQL_CreateTable(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || strlen(error) > 0)
	{
		SetFailState("(SQL_CreateTable) Fail at Query: %s", error);
		return;
	}
	delete results;
}

void LoadClientSettings(int client)
{
	char sCommunityID[64];
	if (!GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID)))
	{
		LogError("Auth failed for client index %d", client);
		return;
	}
	
	char LoadQuery[512];
	Format(LoadQuery, sizeof(LoadQuery), "SELECT * FROM `%s` WHERE steamid = '%s'", Table_Name, sCommunityID);
	
	ddb.Query(SQL_LoadClientStats, LoadQuery, GetClientUserId(client));
}

public void SQL_LoadClientStats(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientOfUserId(data);
	
	if (!IsValidClient(client) || IsFakeClient(client))
		return;
	
	if (db == null || strlen(error) > 0)
	{
		SetFailState("(SQL_LoadClientStats) Fail at Query: %s", error);
		return;
	}
	else
	{
		if(!results.HasResults || !results.FetchRow())
		{
			char sCommunityID[64];
			GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID));
			
			char InsertQuery[512];
			Format(InsertQuery, sizeof(InsertQuery), "INSERT INTO `%s` VALUES(NULL,'%s','1','5', '255 255 255', '255 0 0');", Table_Name, sCommunityID);
			ddb.Query(SQL_InsertCallback, InsertQuery, GetClientUserId(client));
		}
		else
		{
			int show;
			show = results.FetchInt(2);
			if(show == 1)	text_show[client] = true;
			else text_show[client] = false;
			
			results.FetchString(3, text_size[client], 32);
			results.FetchString(4, text_color_normal[client], 32);
			results.FetchString(5, text_color_kill[client], 32);
			
			SayingSettings[client] = 0;
		}
	}
}

public void SQL_InsertCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || strlen(error) > 0)
	{
		SetFailState("SQL_InsertCallback) Fail at Query: %s", error);
		return;
	}
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int idamage = event.GetInt("dmg_health");
	//int hitgroup = event.GetInt("hitgroup");
	int health = GetClientHealth(victim);
	
	if(!IsValidClient(attacker) || IsFakeClient(attacker) || !text_show[attacker])	return;
	
	float pos[3], clientEye[3], clientAngle[3];
	GetClientEyePosition(attacker, clientEye);
	GetClientEyeAngles(attacker, clientAngle);
	
	TR_TraceRayFilter(clientEye, clientAngle, MASK_SOLID, RayType_Infinite, HitSelf, attacker);
	
	if (TR_DidHit(INVALID_HANDLE))	TR_GetEndPosition(pos);
	
	char damage[8];
	IntToString(idamage, damage, sizeof(damage));
	
	if(health < 1)	ShowDamageText(attacker, pos, clientAngle, damage, true);
	else	ShowDamageText(attacker, pos, clientAngle, damage, false);
}

// Edit from
// https://forums.alliedmods.net/showpost.php?p=2523113&postcount=8
stock int ShowDamageText(int client, float fPos[3], float fAngles[3], char[] sText, bool kill) 
{ 
	int entity = CreateEntityByName("point_worldtext"); 
	
	if(entity == -1)	return entity; 

	DispatchKeyValue(entity, "message", sText); 
	DispatchKeyValue(entity, "textsize", text_size[client]);
	
	if(kill)	DispatchKeyValue(entity, "color", text_color_kill[client]); 
	else DispatchKeyValue(entity, "color", text_color_normal[client]); 

	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);  
	
	SDKHook(entity, SDKHook_SetTransmit, SetTransmit);
	TeleportEntity(entity, fPos, fAngles, NULL_VECTOR);
	
	CreateTimer(0.5, KillText, EntIndexToEntRef(entity));
    
	return entity; 
} 

public Action KillText(Handle timer, int ref)
{
	int entity = EntRefToEntIndex(ref);
	if(entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))	return;
	SDKUnhook(entity, SDKHook_SetTransmit, SetTransmit);
	AcceptEntityInput(entity, "kill");
}

public bool HitSelf(int entity, int contentsMask, any data)
{
	if (entity == data)	return false;
	return true;
}

public Action SetTransmit(int client, int entity) 
{ 
	int owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	if(client != owner)	return Plugin_Handled;
	return Plugin_Continue; 
}  

public Action Command_DmgText(int client, int args)
{
	if (IsValidClient(client) && !IsFakeClient(client))
	{
		ShowSettingsMenu(client);
	}
	return Plugin_Handled;
}

public void ShowSettingsMenu(int client)
{
	Menu dmg_menu = new Menu(DMGMenuHandler);
	
	char dmgmenutitle[512];
	Format(dmgmenutitle, sizeof(dmgmenutitle), "%T", "Menu Settings Title", client);
	dmg_menu.SetTitle(dmgmenutitle);
	
	char settings[PLATFORM_MAX_PATH];
	if(text_show[client])	Format(settings, sizeof(settings), "%T", "Menu Settings Show", client, text_size[client], text_color_normal[client], text_color_kill[client]);
	else	Format(settings, sizeof(settings), "%T", "Menu Settings Hide", client, text_size[client], text_color_normal[client], text_color_kill[client]);
	dmg_menu.AddItem("settings", settings);
		
	if(text_show[client])
	{
		char hide[PLATFORM_MAX_PATH];
		Format(hide, sizeof(hide), "%T", "Menu Hide Text", client);
		dmg_menu.AddItem("hide", hide);
	}
	else
	{
		char show[PLATFORM_MAX_PATH];
		Format(show, sizeof(show), "%T", "Menu Show Text", client);
		dmg_menu.AddItem("show", show);
	}
		
	char size[PLATFORM_MAX_PATH];
	Format(size, sizeof(size), "%T", "Menu Text Size", client);
	dmg_menu.AddItem("size", size);
		
	char normal_color[PLATFORM_MAX_PATH];
	Format(normal_color, sizeof(normal_color), "%T", "Menu Noraml Color", client);
	dmg_menu.AddItem("normal_color", normal_color);
		
	char kill_color[PLATFORM_MAX_PATH];
	Format(kill_color, sizeof(kill_color), "%T", "Menu Kill Color", client);
	dmg_menu.AddItem("kill_color", kill_color);
		
	dmg_menu.Display(client, 0);
}

public int DMGMenuHandler(Menu menu, MenuAction action, int client,int param)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char menuitem[20];
			menu.GetItem(param, menuitem, sizeof(menuitem));
			
			if(StrEqual(menuitem, "settings"))
			{
				ShowSettingsMenu(client);
			}
			else if(StrEqual(menuitem, "show"))
			{
				text_show[client] = true;
				ShowSettingsMenu(client);
			}
			else if(StrEqual(menuitem, "hide"))
			{
				text_show[client] = false;
				ShowSettingsMenu(client);
			}
			else if(StrEqual(menuitem, "size"))
			{
				CPrintToChat(client, "%T", "Say Size", client);
				SayingSettings[client] = 1;
			}
			else if(StrEqual(menuitem, "normal_color"))
			{
				CPrintToChat(client, "%T", "Say Normal Color", client);
				SayingSettings[client] = 2;
			}
			else if(StrEqual(menuitem, "kill_color"))
			{
				CPrintToChat(client, "%T", "Say Kill Color", client);
				SayingSettings[client] = 3;
			}
		}
	}
}

public void OnClientDisconnect(int client)
{
	if(IsValidClient(client) && !IsFakeClient(client))	SaveClientSettings(client);
}

void SaveClientSettings(int client)
{
	char sCommunityID[64];
	if (!GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID)))
	{
		LogError("Auth failed for client index %d", client);
		return;
	}
	
	int show;
	if(text_show[client])	show = 1;
	else	show = 0;
			
	char SaveQuery[512];
	Format(SaveQuery, sizeof(SaveQuery),
	"UPDATE `%s` SET showtext = '%i', textsize = '%s', normal_color ='%s', kill_color='%s' WHERE steamid = '%s';",
	Table_Name,
	client,
	show,
	text_size[client], 
	text_color_normal[client], 
	text_color_kill[client], 
	sCommunityID);
	
	ddb.Query(SQL_SaveCallback, SaveQuery, GetClientUserId(client))
}

public void SQL_SaveCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || strlen(error) > 0)
	{
		SetFailState("(SQL_SaveClientStats) Fail at Query: %s", error);
		return;
	}
}

public Action Command_Say(int client, int args)
{
	if(!IsValidClient(client) || IsFakeClient(client) || SayingSettings[client] == 0)	return Plugin_Continue;
	
	char arg[64];
	GetCmdArgString(arg, sizeof(arg));
	StripQuotes(arg);
	
	if(StrEqual(arg, "!cancel"))
	{
		CPrintToChat(client, "%T", "Say Cancel", client);
		SayingSettings[client] = 0;
		ShowSettingsMenu(client);
	}
	else
	{
		if(SayingSettings[client] == 1)
		{
			text_size[client] = arg;
			SayingSettings[client] = 0;
			
			CPrintToChat(client, "%T", "Size Is", client, text_size[client]);
		}
		else if(SayingSettings[client] == 2)
		{
			text_color_normal[client] = arg;
			SayingSettings[client] = 0;
			
			CPrintToChat(client, "%T", "Normal RGB Color Is", client, text_color_normal[client]);
		}
		else if(SayingSettings[client] == 3)
		{
			text_color_kill[client] = arg;
			SayingSettings[client] = 0;
			
			CPrintToChat(client, "%T", "Kill RGB Color Is", client, text_color_kill[client]);
		}
	}
	return Plugin_Handled;
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++) 
	{
		if (IsValidClient(i) && !IsFakeClient(i))
		{
			SaveClientSettings(i);
		}
	}
}

stock bool IsValidClient(int client)
{
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	if (!IsClientConnected(client)) return false;
	return IsClientInGame(client);
}