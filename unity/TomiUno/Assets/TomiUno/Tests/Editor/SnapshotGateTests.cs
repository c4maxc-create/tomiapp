using NUnit.Framework;
using Tomi.Uno;

public sealed class SnapshotGateTests
{
    static TableSnapshot State(int revision, int turn = 0)
    {
        return new TableSnapshot { id="match-1", revision=revision, mySeat=0, turn=turn,
            status="playing", hand=new[]{new CardState{id="red-7-0",color="red",value="7"}},
            playableCardIds=new[]{"red-7-0"} };
    }
    [Test] public void DuplicateOrOlderRepliesCannotRestoreAnOldHand()
    {
        var gate=new SnapshotGate(); Assert.IsTrue(gate.Accept(State(3)));
        Assert.IsFalse(gate.Accept(State(2))); Assert.IsFalse(gate.Accept(State(3)));
        Assert.AreEqual(3,gate.Current.revision);
    }
    [Test] public void ServerPlayableIdsCannotAuthorizeAnUnownedCardOrAnotherTurn()
    {
        var gate=new SnapshotGate();gate.Accept(State(1));Assert.IsTrue(gate.CanPlay("red-7-0"));
        Assert.IsFalse(gate.CanPlay("opponent-private-card"));
        gate.Accept(State(2,1));Assert.IsFalse(gate.CanPlay("red-7-0"));
    }
    [Test] public void MalformedHandDoesNotReplaceAcceptedState()
    {
        var gate=new SnapshotGate();gate.Accept(State(1));var bad=State(2);
        bad.hand=new[]{new CardState{id="duplicate"},new CardState{id="duplicate"}};
        Assert.IsFalse(gate.Accept(bad));Assert.AreEqual(1,gate.Current.revision);
    }
    [Test] public void LateReplyForAnotherMatchRequiresExplicitSessionClear()
    {
        var gate=new SnapshotGate();gate.Accept(State(1));var other=State(9);other.id="another-match";
        Assert.IsFalse(gate.Accept(other));gate.Clear();Assert.IsTrue(gate.Accept(other));
    }
    [Test] public void LogoutClearsPrivateCardsAndEligibility()
    {
        var gate=new SnapshotGate();gate.Accept(State(1));gate.Clear();
        Assert.IsNull(gate.Current);Assert.IsFalse(gate.CanPlay("red-7-0"));
    }
}
