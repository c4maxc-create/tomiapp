using System;
using System.Collections.Generic;
using UnityEngine;

namespace Tomi.Uno
{
    // Only the requesting player's hand belongs in this transport object.
    // Same field names as server/src/game_engine.mjs publicGameState.
    [Serializable] public sealed class CardState
    {
        public string id, color, value;
        public string Symbol => value == "draw2" ? "+2" : value == "wild4" ? "+4" :
            value == "wild" ? "W" : value == "skip" ? "X" : value == "reverse" ? "R" : value;
    }
    [Serializable] public sealed class PlayerState { public int seat, cardCount; public bool bot; }
    [Serializable] public sealed class TableSnapshot
    {
        public string id, status, activeColor;
        public int revision, sequence, mySeat, turn, direction, deckCount;
        public long serverTime, deadlineAt;
        public CardState[] hand;
        public CardState topCard;
        public string[] playableCardIds;
        public PlayerState[] players;
        public bool canDraw, canPass;
    }
    [Serializable] public sealed class ActionIntent
    {
        public string requestId, type, cardId, color;
        public int revision;
        public bool uno;
    }
    public sealed class SnapshotGate
    {
        public TableSnapshot Current { get; private set; }
        public bool Accept(TableSnapshot next)
        {
            if (next == null || string.IsNullOrEmpty(next.id)) return false;
            if (Current != null && (next.id != Current.id || next.revision <= Current.revision)) return false;
            var ids = new HashSet<string>();
            if (next.hand != null)
                foreach (var card in next.hand)
                    if (card == null || string.IsNullOrEmpty(card.id) || !ids.Add(card.id)) return false;
            Current = next;
            return true;
        }
        public bool CanPlay(string id)
        {
            return Current != null && Current.status == "playing" && Current.turn == Current.mySeat &&
                Array.Exists(Current.hand ?? Array.Empty<CardState>(), c => c.id == id) &&
                Array.IndexOf(Current.playableCardIds ?? Array.Empty<string>(), id) >= 0;
        }
        public void Clear() { Current = null; }
    }
}
