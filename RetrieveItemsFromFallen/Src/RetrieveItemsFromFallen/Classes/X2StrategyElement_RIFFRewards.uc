class X2StrategyElement_RIFFRewards extends X2StrategyElement_DefaultRewards config (RIFF);

var config array<name> FallenItemsToRetrieve;
var config array<name> BlacklistedItems;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Rewards;

	Rewards.AddItem(CreateRetriveItemRewardTemplate());

	return Rewards;
}

static function X2DataTemplate CreateRetriveItemRewardTemplate()
{
	local X2RewardTemplate Template;

	`CREATE_X2Reward_TEMPLATE(Template, 'Reward_RetrieveItem');	

	Template.IsRewardAvailableFn = IsRetrieveItemRewardAvailable;
	Template.GenerateRewardFn = GenerateItemsToRetrieveReward;
	Template.SetRewardFn = SetItemReward;
	Template.GiveRewardFn = GiveRetrievedItemsReward;	
	Template.GetRewardStringFn = GetItemsToRetrieveRewardString;
	Template.GetRewardDetailsStringFn = GetItemsToRetrieveRewardString;	

	return Template;
}

static function bool IsRetrieveItemRewardAvailable(optional XComGameState NewGameState, optional StateObjectReference AuxRef)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local StateObjectReference UnitRef;
	local XComGameState_Unit Unit;	

	XComHQ = `XCOMHQ;

	// Validates whether we have any units eligible for this reward
	foreach XComHQ.DeadCrew(UnitRef)
	{
		Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
		if (Unit == none) continue;			
		if (IsUnitEligible(Unit)) return true;		
	}

	return false;
}

static function GenerateItemsToRetrieveReward(XComGameState_Reward RewardState, XComGameState NewGameState, optional float RewardScalar = 1.0, optional StateObjectReference AuxRef)
{
	local XComGameState_StoreItemsForRetrieval StorageContainer;
	local StateObjectReference UnitRef, ItemRef;
	local array<StateObjectReference> ItemRefs;
	local XComGameState_Item Item;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Unit Unit;
	local XComGameState_CovertAction Action;
	local array<XComGameState_Unit> Units;
	local XComGameStateHistory History;

	XComHQ = `XCOMHQ;
	History = `XCOMHISTORY;

	// Should be kept consistent with IsRetrieveItemRewardAvailable(). Grab eligible units
	foreach XComHQ.DeadCrew(UnitRef)
	{
		Unit = XComGameState_Unit(History.GetGameStateForObjectID(UnitRef.ObjectID));
		if (Unit == none) continue;
		if (IsUnitEligible(Unit)) Units.AddItem(Unit);
	}

	// If not units are found, something is terribly wrong
	if (Units.Length <= 0) 
	{
		`REDSCREEN("Welp, cannot get any units to retrieve item(s) from. This should have been prevented in IsRetrieveItemRewardAvailable");
		return;
	}

	// Randomly pick a unit
	Unit = Units[`SYNC_RAND_STATIC(Units.Length)];
	
	// Grab all items that we want to retrieve from the dead body
	foreach Unit.InventoryItems(ItemRef)
	{
		Item = XComGameState_Item(History.GetGameStateForObjectID(ItemRef.ObjectID));
		if (Item == none) continue;

		if (default.BlacklistedItems.Find(Item.GetMyTemplateName()) != INDEX_NONE) continue;

		ItemRefs.AddItem(ItemRef);
	}

	// This state serves as a place for us to store the unit we have chosen and the items we will retrieve as part of the reward
	StorageContainer = XComGameState_StoreItemsForRetrieval(NewGameState.CreateNewStateObject(class'XComGameState_StoreItemsForRetrieval'));
	StorageContainer.UnitRef = Unit.GetReference();
	StorageContainer.ItemRefs = ItemRefs;

	// We also link the reward to the covert action for easy access later
	Action = XComGameState_CovertAction(NewGameState.GetGameStateForObjectID(AuxRef.ObjectID));
	if (Action != none) Action.StoredRewardRef = RewardState.GetReference();
	
	// Assign the container to the reward. This state will be cleaned up by the game once this CA is done
	RewardState.RewardObjectReference = StorageContainer.GetReference();
}

static function GiveRetrievedItemsReward(XComGameState NewGameState, XComGameState_Reward RewardState, optional StateObjectReference AuxRef, optional bool bOrder = false, optional int OrderHours = -1)
{
	local XComGameState_StoreItemsForRetrieval StorageContainer;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameStateHistory History;
	local XComGameState_Unit Unit;
	local XComGameState_Item Item;
	local StateObjectReference ItemRef;
	local bool bHQUpdated;

	XComHQ = `XCOMHQ;
	History = `XCOMHISTORY;

	// Grab our container
	StorageContainer = XComGameState_StoreItemsForRetrieval(History.GetGameStateForObjectID(RewardState.RewardObjectReference.ObjectID));	
	Unit = XComGameState_Unit(History.GetGameStateForObjectID(StorageContainer.UnitRef.ObjectID));
	Unit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
	XComHQ = XComGameState_HeadquartersXCom(NewGameState.ModifyStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));

	Unit.bBodyRecovered = true;

	// Loop through the items that we will retrieve and put in XCOM HQ
	foreach StorageContainer.ItemRefs(ItemRef)
	{
		Item = XComGameState_Item(History.GetGameStateForObjectID(ItemRef.ObjectID));
		if (Unit.RemoveItemFromInventory(Item, NewGameState))
		{
			if (XComHQ.PutItemInInventory(NewGameState, Item)) bHQUpdated = true;			
		}
	}
	
	// If for some reason we failed to put any of the items into XCOM HQ, we should purge the XCOMHQ state from our game state
	if (!bHQUpdated)
	{
		NewGameState.PurgeGameStateForObjectID(XComHQ.ObjectID);
	}
}

static function string GetItemsToRetrieveRewardString(XComGameState_Reward RewardState)
{
	local XComGameState_StoreItemsForRetrieval StorageContainer;
	local XComGameState_Item Item;
	local StateObjectReference ItemRef;
	local XComGameStateHistory History;
	local array<string> ItemsFriendlyNames;
	local string ItemList;	

	History = `XCOMHISTORY;
	StorageContainer = XComGameState_StoreItemsForRetrieval(History.GetGameStateForObjectID(RewardState.RewardObjectReference.ObjectID));

	if (StorageContainer == none) return "<No items found>";

	foreach StorageContainer.ItemRefs(ItemRef)
	{		
		Item = XComGameState_Item(History.GetGameStateForObjectID(ItemRef.ObjectID));
		if (Item == none) continue;
		
		ItemsFriendlyNames.AddItem(Item.GetMyTemplate().GetItemFriendlyName());
	}

	JoinArray(ItemsFriendlyNames, ItemList, ", ");

	return ItemList;
}

// --------------
// HELPERS
// --------------
static function bool IsUnitEligible(XComGameState_Unit Unit)
{
	local XComGameState_Item Item;
	local StateObjectReference ItemRef;
	local XComGameState_CovertAction Action;
	local XComGameStateHistory History;
	local XComGameState_Reward Reward;
	local XComGameState_StoreItemsForRetrieval StorageContainer;

	// If body has been recovered, there is no point to this
	if (Unit.bBodyRecovered) return false;

	History = `XCOMHISTORY;

	// Check if there is already a CA with this unit's body to be retrieved
	foreach History.IterateByClassType(class'XComGameState_CovertAction', Action)
	{
		if (Action.bAvailable || Action.bStarted)
		{
			Reward = XComGameState_Reward(History.GetGameStateForObjectID(Action.StoredRewardRef.ObjectID));
			StorageContainer = XComGameState_StoreItemsForRetrieval(History.GetGameStateForObjectID(Reward.RewardObjectReference.ObjectID));

			if (StorageContainer != none && StorageContainer.UnitRef == Unit.GetReference()) return false;
		}
	}

	// If there is no item retriction, we will allow it
	if (default.FallenItemsToRetrieve.Length <= 0) return true;

	// Check item restriction
	foreach Unit.InventoryItems(ItemRef)
	{
		Item = XComGameState_Item(History.GetGameStateForObjectID(ItemRef.ObjectID));
		if (Item == none) continue;		

		if (default.FallenItemsToRetrieve.Find(Item.GetMyTemplateName()) != INDEX_NONE)
			return true;
	}

	return false;
}
