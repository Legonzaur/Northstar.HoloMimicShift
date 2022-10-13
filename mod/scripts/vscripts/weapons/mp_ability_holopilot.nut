global function OnWeaponPrimaryAttack_holopilot
global function PlayerCanUseDecoy

global const int DECOY_FADE_DISTANCE = 16000 //Really just an arbitrarily large number
global const float DECOY_DURATION = 20.0

global const vector HOLOPILOT_ANGLE_SEGMENT = < 0, 25, 0 >

#if SERVER
global function CodeCallback_PlayerDecoyDie
global function CodeCallback_PlayerDecoyDissolve
global function CodeCallback_PlayerDecoyRemove
global function CodeCallback_PlayerDecoyStateChange
global function CreateHoloPilotDecoys
global function SetupDecoy_Common

global function Decoy_Init

#if MP
global function GetDecoyActiveCountForPlayer
#endif //if MP

#endif //if server

const float PHASE_REWIND_PATH_SNAPSHOT_INTERVAL = 0.1
struct
{
	table< entity, int > playerToDecoysActiveTable //Mainly used to track stat for holopilot unlock

}
file

global table< entity > playerDecoyList //CUSTOM used to track the decoy the user will be teleported to

#if SERVER

void function Decoy_Init()
{
	#if MP
		RegisterSignal( "CleanupFXAndSoundsForDecoy" )
	#endif

	RegisterSignal( "StopAllRecordings" )
}

void function CleanupExistingDecoy( entity decoy )
{
	if ( IsValid( decoy ) ) //This cleanup function is called from multiple places, so check that decoy is still valid before we try to clean it up again
	{
		decoy.Decoy_Dissolve()
		CleanupFXAndSoundsForDecoy( decoy )
	}
}

void function CleanupFXAndSoundsForDecoy( entity decoy )
{
	if ( !IsValid( decoy ) )
		return

	decoy.Signal( "CleanupFXAndSoundsForDecoy" )

	// foreach( fx in decoy.decoy.fxHandles )
	// {
	// 	if ( IsValid( fx ) )
	// 	{
	// 		fx.ClearParent()
	// 		EffectStop( fx )
	// 	}
	// }

	// decoy.decoy.fxHandles.clear() //probably not necessary since decoy is already being cleaned up, just for throughness.

	// foreach ( loopingSound in decoy.decoy.loopingSounds )
	// {
	// 	StopSoundOnEntity( decoy, loopingSound )
	// }

	// decoy.decoy.loopingSounds.clear()
}

void function OnHoloPilotDestroyed( entity decoy )
{
	EmitSoundAtPosition( TEAM_ANY, decoy.GetOrigin(), "holopilot_end_3P" )

	entity bossPlayer = decoy.GetBossPlayer()
	if ( IsValid( bossPlayer ) ){
		if(bossPlayer in playerDecoyList){
			if(decoy == playerDecoyList[bossPlayer])
				delete playerDecoyList[bossPlayer]
		}
		EmitSoundOnEntityOnlyToPlayer( bossPlayer, bossPlayer, "holopilot_end_1P" )
	}

	CleanupFXAndSoundsForDecoy( decoy )
}

void function CodeCallback_PlayerDecoyDie( entity decoy, int currentState ) //All Die does is play the death animation. Eventually calls CodeCallback_PlayerDecoyDissolve too
{
	//PrintFunc()
	OnHoloPilotDestroyed( decoy )
}

void function CodeCallback_PlayerDecoyDissolve( entity decoy, int currentState )
{
	//PrintFunc()
	OnHoloPilotDestroyed( decoy )
}


void function CodeCallback_PlayerDecoyRemove( entity decoy, int currentState )
{
	//PrintFunc()
}


void function CodeCallback_PlayerDecoyStateChange( entity decoy, int previousState, int currentState )
{
	//PrintFunc()
}

#endif


var function OnWeaponPrimaryAttack_holopilot( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	entity weaponOwner = weapon.GetWeaponOwner()
	Assert( weaponOwner.IsPlayer() )

	if ( !PlayerCanUseDecoy( weaponOwner ) )
		return 0

#if SERVER
	if ( weaponOwner in playerDecoyList ){
		CreateHoloPilotDecoys( weaponOwner, 1 )
		entity decoy = playerDecoyList[ weaponOwner ]
		if(weaponOwner.GetOffhandWeapon(1).GetWeaponClassName() == "mp_ability_holopilot"){
			weaponOwner.GetOffhandWeapon(1).SetWeaponPrimaryClipCount(0)
		}
		PlayerUsesHoloRewind(weaponOwner, decoy)
		if(GetCurrentPlaylistName() == "lts"){
			if(PlayerHasBattery(weaponOwner)){
				//Rodeo_TakeBatteryAwayFromPilot(weaponOwner)
			}
		}
		PlayerUsedOffhand( weaponOwner, weapon )
	}else{
		entity decoy = CreateHoloPilotDecoys( weaponOwner, 1, true )
		
		thread MimicOwner( weaponOwner, decoy )
		playerDecoyList[ weaponOwner ] <- decoy
		return 0
	}
#else
	Rumble_Play( "rumble_holopilot_activate", {} )
#endif

	return weapon.GetWeaponSettingInt( eWeaponVar.ammo_min_to_fire )
}

#if SERVER
entity function CreateHoloPilotDecoys( entity player, int numberOfDecoysToMake = 1, bool isFakePlayer = false )
{
	//player.Signal( "StopAllRecordings" )
	Assert( numberOfDecoysToMake > 0  )
	Assert( player )
	
	float displacementDistance = 30.0

	bool setOriginAndAngles = numberOfDecoysToMake > 1

	float stickPercentToRun = 0.65
	if ( setOriginAndAngles )
		stickPercentToRun = 0.0

	entity decoy
	for( int i = 0; i < numberOfDecoysToMake; ++i )
	{
		if(isFakePlayer){
			decoy = CreateElitePilot( player.GetTeam(), player.GetOrigin(), player.GetAngles() )
			decoy.SetModel( player.GetModelName() )
			DispatchSpawn( decoy )
			decoy.SetModel( player.GetModelName() )
			decoy.SetTitle( player.GetPlayerName() )
			decoy.SetScriptName( player.GetPlayerName() + "_decoy" )
			thread KillAfterTimeout( DECOY_DURATION, decoy, player )
			decoy.kv.VisibilityFlags = ENTITY_VISIBLE_TO_EVERYONE
			decoy.TakeWeaponNow(decoy.GetActiveWeapon().GetWeaponClassName())
			decoy.GiveWeapon(player.GetActiveWeapon().GetWeaponClassName())
		}else{
			decoy = player.CreatePlayerDecoy( stickPercentToRun )
			decoy.EnableAttackableByAI( 50, 0, AI_AP_FLAG_NONE )
			decoy.SetTimeout( DECOY_DURATION )
		}
		

		decoy.SetMaxHealth( 50 )
		decoy.SetHealth( 50 )
		SetObjectCanBeMeleed( decoy, true )

		if ( setOriginAndAngles )
		{
			vector angleToAdd = CalculateAngleSegmentForDecoy( i, HOLOPILOT_ANGLE_SEGMENT )
			vector normalizedAngle = player.GetAngles() +  angleToAdd
			normalizedAngle.y = AngleNormalize( normalizedAngle.y ) //Only care about changing the yaw
			decoy.SetAngles( normalizedAngle )

			vector forwardVector = AnglesToForward( normalizedAngle )
			forwardVector *= displacementDistance
			decoy.SetOrigin( player.GetOrigin() + forwardVector ) //Using player origin instead of decoy origin as defensive fix, see bug 223066
			PutEntityInSafeSpot( decoy, player, null, player.GetOrigin(), decoy.GetOrigin()  )
		}

		SetupDecoy_Common( player, decoy )
		#if MP
					thread MonitorDecoyActiveForPlayer( decoy, player )
			#endif
	}
	
	#if BATTLECHATTER_ENABLED
		PlayBattleChatterLine( player, "bc_pHolo" )
	#endif
	return decoy
}

void function SetupDecoy_Common( entity player, entity decoy ) //functioned out mainly so holopilot execution can call this as well
{
	decoy.SetDeathNotifications( true )
	decoy.SetPassThroughThickness( 0 )
	decoy.SetNameVisibleToOwner( true )
	decoy.SetNameVisibleToFriendly( true )
	decoy.SetNameVisibleToEnemy( true )
	// decoy.SetDecoyRandomPulseRateMax( 0.5 ) //pulse amount per second
	// decoy.SetFadeDistance( DECOY_FADE_DISTANCE )

	int friendlyTeam = decoy.GetTeam()
	EmitSoundOnEntityToTeam( decoy, "holopilot_loop", friendlyTeam  ) //loopingSound
	EmitSoundOnEntityToEnemies( decoy, "holopilot_loop_enemy", friendlyTeam  ) ///loopingSound
	// decoy.decoy.loopingSounds = [ "holopilot_loop", "holopilot_loop_enemy" ]

	Highlight_SetFriendlyHighlight( decoy, "friendly_player_decoy" )
	Highlight_SetOwnedHighlight( decoy, "friendly_player_decoy" )
	decoy.e.hasDefaultEnemyHighlight = true
	SetDefaultMPEnemyHighlight( decoy )

	int attachID = decoy.LookupAttachment( "CHESTFOCUS" )

	#if MP
	var childEnt = player.FirstMoveChild()
	while ( childEnt != null )
	{
		expect entity( childEnt )

		bool isBattery = false
		bool createHologram = false
		switch( childEnt.GetClassName() )
		{
			case "item_titan_battery":
			{
				isBattery = true
				createHologram = true
				break
			}

			case "item_flag":
			{
				createHologram = true
				break
			}
		}

		asset modelName = childEnt.GetModelName()
		if ( createHologram && modelName != $"" && childEnt.GetParentAttachment() != "" )
		{
			entity decoyChildEnt = CreatePropDynamic( modelName, <0, 0, 0>, <0, 0, 0>, 0 )
			decoyChildEnt.Highlight_SetInheritHighlight( true )
			decoyChildEnt.SetParent( decoy, childEnt.GetParentAttachment() )

			if ( isBattery )
				thread Decoy_BatteryFX( decoy, decoyChildEnt )
			else
				thread Decoy_FlagFX( decoy, decoyChildEnt )
		}

		childEnt = childEnt.NextMovePeer()
	}
	#endif // MP

	entity holoPilotTrailFX = StartParticleEffectOnEntity_ReturnEntity( decoy, HOLO_PILOT_TRAIL_FX, FX_PATTACH_POINT_FOLLOW, attachID )
	SetTeam( holoPilotTrailFX, friendlyTeam )
	holoPilotTrailFX.kv.VisibilityFlags = ENTITY_VISIBLE_TO_FRIENDLY

	// decoy.decoy.fxHandles.append( holoPilotTrailFX )
	// decoy.SetFriendlyFire( false )
	 // decoy.SetKillOnCollision( false )
}

	vector function CalculateAngleSegmentForDecoy( int loopIteration, vector angleSegment )
	{
		if ( loopIteration == 0 )
			return < 0, 0, 0 >

		if ( loopIteration % 2 == 0  )
			return ( loopIteration / 2 ) * angleSegment * -1
		else
			return ( ( loopIteration / 2 ) + 1 ) * angleSegment

		unreachable
	}

	#if MP
	void function Decoy_BatteryFX( entity decoy, entity decoyChildEnt )
	{
		decoy.EndSignal( "OnDeath" )
		decoy.EndSignal( "CleanupFXAndSoundsForDecoy" )
		Battery_StartFX( decoyChildEnt )

		OnThreadEnd(
			function() : ( decoyChildEnt )
			{
				Battery_StopFX( decoyChildEnt )
				if ( IsValid( decoyChildEnt ) )
					decoyChildEnt.Destroy()
			}
		)

		WaitForever()
	}

	void function Decoy_FlagFX( entity decoy, entity decoyChildEnt )
	{
		decoy.EndSignal( "OnDeath" )
		decoy.EndSignal( "CleanupFXAndSoundsForDecoy" )

		SetTeam( decoyChildEnt, decoy.GetTeam() )
		entity flagTrailFX = StartParticleEffectOnEntity_ReturnEntity( decoyChildEnt, GetParticleSystemIndex( FLAG_FX_ENEMY ), FX_PATTACH_POINT_FOLLOW, decoyChildEnt.LookupAttachment( "fx_end" ) )
		flagTrailFX.kv.VisibilityFlags = ENTITY_VISIBLE_TO_ENEMY

		OnThreadEnd(
			function() : ( flagTrailFX, decoyChildEnt )
			{
				if ( IsValid( flagTrailFX ) )
					flagTrailFX.Destroy()

				if ( IsValid( decoyChildEnt ) )
					decoyChildEnt.Destroy()
			}
		)

		WaitForever()
	}

	void function MonitorDecoyActiveForPlayer( entity decoy, entity player )
		{
			if ( player in file.playerToDecoysActiveTable )
				++file.playerToDecoysActiveTable[ player ]
			else
				file.playerToDecoysActiveTable[ player ] <- 1

			decoy.EndSignal( "OnDestroy" ) //Note that we do this OnDestroy instead of the inbuilt OnHoloPilotDestroyed() etc functions so there is a bit of leeway after the holopilot starts to die/is fully invisible before being destroyed
			player.EndSignal( "OnDestroy" )

			OnThreadEnd(
			function() : ( player )
				{
					if( IsValid( player ) )
					{
						Assert( player in file.playerToDecoysActiveTable )
						--file.playerToDecoysActiveTable[ player ]
					}

				}
			)

			WaitForever()
		}

		int function GetDecoyActiveCountForPlayer( entity player )
		{
			if ( !(player in file.playerToDecoysActiveTable ))
				return 0

			return file.playerToDecoysActiveTable[player ]
		}

	#endif // MP

void function MimicOwner( entity player, entity decoy )
{
	EndSignal( decoy, "OnDeath" )
	EndSignal( player, "OnDeath" )
	EndSignal( decoy, "OnDestroy" )
	EndSignal( player, "OnDestroy" )
	EndSignal( player, "StopAllRecordings" )

	entity ref = CreateScriptMover( player.GetOrigin() )
	decoy.Hide()

	OnThreadEnd(
		function() : ( ref, player, decoy )
		{
			if( IsValid( player ) )
			{
				player.StopRecordingAnimation()
			}
			ref.Destroy()

			if ( IsValid( player ) ){
			if(player in playerDecoyList){
				if(decoy == playerDecoyList[player])
					delete playerDecoyList[player]
			}
			//EmitSoundOnEntityOnlyToPlayer( player, player, "holopilot_end_1P" )
			}
		}
	)

	player.StartRecordingAnimation( ref.GetOrigin(), ref.GetAngles() )

	wait 1

	var rec = player.StopRecordingAnimation()

	decoy.PlayRecordedAnimation( rec, <0,0,0>, <0,0,0>, DEFAULT_SCRIPTED_ANIMATION_BLEND_TIME, ref )
	decoy.Show()

	for(;;)
	{
		player.StartRecordingAnimation( ref.GetOrigin(), ref.GetAngles() )

		wait 1

		var recording = player.StopRecordingAnimation()

		decoy.PlayRecordedAnimation( recording, <0,0,0>, <0,0,0>, DEFAULT_SCRIPTED_ANIMATION_BLEND_TIME, ref )
	}
	
}

void function KillAfterTimeout( float time, entity decoy, entity player )
{
	EndSignal( decoy, "OnDeath" )
	EndSignal( decoy, "OnDestroy" )
	

	wait time	
	if(IsValid(player)){
		if(player in playerDecoyList){
		if(decoy == playerDecoyList[player]){
			delete playerDecoyList[player]
			EmitSoundOnEntityOnlyToPlayer( player, player, "holopilot_end_1P" )
		}
			
		}
	
		print(player.GetOffhandWeapon(1).GetWeaponClassName())
		if(player.GetOffhandWeapon(1) && player.GetOffhandWeapon(1).GetWeaponClassName() == "mp_ability_holopilot"){
			player.GetOffhandWeapon(1).SetWeaponPrimaryClipCount(0)
		}
	}
	
	if(IsAlive(decoy)){
			decoy.Hide()
			decoy.TakeWeaponNow(decoy.GetActiveWeapon().GetWeaponClassName())
			decoy.Destroy()
			
	}

	
}

#endif // SERVER


bool function PlayerCanUseDecoy( entity ownerPlayer ) //For holopilot and HoloPilot Nova. No better place to put this for now
{
	if ( !ownerPlayer.IsZiplining() )
	{
		if ( ownerPlayer.IsTraversing() )
			return false

		if ( ownerPlayer.ContextAction_IsActive() ) //Stops every single context action from letting decoy happen, including rodeo, melee, embarking etc
			return false
	}

	//Do we need to check isPhaseShifted here? Re-examine when it's possible to get both Phase and Decoy (maybe through burn cards?)
	if(ownerPlayer.IsPhaseShifted())
		return false
	return true
}

#if SERVER
void function PlayerUsesHoloRewind( entity player, entity decoy )
{
	thread PlayerUsesHoloRewindThreaded( player, decoy )
}

void function PlayerUsesHoloRewindThreaded( entity player, entity decoy )
{
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )
	decoy.EndSignal("OnDestroy")
	decoy.EndSignal("OnDeath")
	entity mover = CreateScriptMover( player.GetOrigin(), player.GetAngles() )
	player.SetParent( mover, "REF" )

	OnThreadEnd( function() : ( player, mover, decoy )
	{
		PutEntityInSafeSpot( player, decoy, null, decoy.GetOrigin(), player.GetOrigin()  )
		player.SetAngles(decoy.GetAngles())
		player.SetVelocity(decoy.GetVelocity())
		CancelPhaseShift( player )
		player.DeployWeapon()
		player.SetPredictionEnabled( true )
		player.ClearParent()
		ViewConeFree( player )
		mover.Destroy()

		print(player.GetOffhandWeapon(1).GetWeaponClassName())
		if(player.GetOffhandWeapon(1) && player.GetOffhandWeapon(1).GetWeaponClassName() == "mp_ability_holopilot"){
			player.GetOffhandWeapon(1).SetWeaponPrimaryClipCount(0)
		}
			
		if(IsAlive(decoy)){
			decoy.Hide()
			decoy.TakeWeaponNow(decoy.GetActiveWeapon().GetWeaponClassName())
			decoy.Destroy()
			
			
		}	
		if ( IsValid( player ) ){
			if(player in playerDecoyList){
				if(decoy == playerDecoyList[player]){
					delete playerDecoyList[player]
					EmitSoundOnEntityOnlyToPlayer( player, player, "holopilot_end_1P" )
				}
					
			}
		}
		//CleanupExistingDecoy(decoy)	
	})

	vector initial_origin = player.GetOrigin()
	vector initial_angle = player.GetAngles()
	array<PhaseRewindData> positions = clone player.p.burnCardPhaseRewindStruct.phaseRetreatSavedPositions

	ViewConeZero( player )
	player.HolsterWeapon()
	player.SetPredictionEnabled( false )
	PhaseShift( player, 0.0, 7 * PHASE_REWIND_PATH_SNAPSHOT_INTERVAL * 1.5 )

	for ( float i = 7; i > 0; i-- )
	{
		initial_origin -= (initial_origin-decoy.GetOrigin())*(1/i)
		initial_angle -= (initial_angle-decoy.GetAngles())*(1/i)
		mover.NonPhysicsMoveTo( initial_origin, PHASE_REWIND_PATH_SNAPSHOT_INTERVAL, 0, 0 )
		mover.NonPhysicsRotateTo( initial_angle, PHASE_REWIND_PATH_SNAPSHOT_INTERVAL, 0, 0 )
		wait PHASE_REWIND_PATH_SNAPSHOT_INTERVAL
	}

	mover.NonPhysicsMoveTo( decoy.GetOrigin(), PHASE_REWIND_PATH_SNAPSHOT_INTERVAL, 0, 0 )
	mover.NonPhysicsRotateTo( decoy.GetAngles(), PHASE_REWIND_PATH_SNAPSHOT_INTERVAL, 0, 0 )
	player.SetVelocity( decoy.GetVelocity() )
}
#endif
