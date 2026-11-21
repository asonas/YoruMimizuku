using YoruMimizuku.Core.Accounts;
using YoruMimizuku.Core.OAuth;
using static YoruMimizuku.Core.Tests.FakeAtproto;

namespace YoruMimizuku.Core.Tests;

public class AccountManagerTests
{
    private static readonly AccountSummary Alice = new(AliceDid, "alice.test");
    private static readonly AccountSummary Bob = new(BobDid, "bob.test");

    private readonly FakeAtproto _server = new();

    [Fact]
    public void NoAccountIsCurrentBeforeAnySignIn()
    {
        var accounts = AccountTestSupport.Manager(_server);

        Assert.Null(accounts.CurrentAccount());
        Assert.Empty(accounts.Summaries());
    }

    [Fact]
    public async Task SigningInStoresTheAccountAndMakesItCurrent()
    {
        var accounts = AccountTestSupport.Manager(_server);

        var summary = await accounts.SignInAsync(_server);

        Assert.Equal(Alice, summary);
        Assert.Equal(Alice, accounts.CurrentAccount());
        Assert.Equal([Alice], accounts.Summaries());
    }

    [Fact]
    public async Task ALaterSignInBecomesCurrentAndAccountsListInSignInOrder()
    {
        var accounts = AccountTestSupport.Manager(_server);

        await accounts.SignInAsync(_server);
        await accounts.SignInAsync(_server, "bob.test", BobDid);

        Assert.Equal(Bob, accounts.CurrentAccount());
        Assert.Equal([Alice, Bob], accounts.Summaries());
    }

    [Fact]
    public async Task SigningInAgainReplacesTheAccountRatherThanListingItTwice()
    {
        var accounts = AccountTestSupport.Manager(_server);

        await accounts.SignInAsync(_server);
        await accounts.SignInAsync(_server);

        Assert.Equal([Alice], accounts.Summaries());
    }

    [Fact]
    public async Task ARejectedSignInStoresNothing()
    {
        var accounts = AccountTestSupport.Manager(_server);

        await Assert.ThrowsAsync<OAuthException>(() => accounts.SignInAsync(_server, "alice.test", signedInAs: BobDid));

        Assert.Null(accounts.CurrentAccount());
        Assert.Empty(accounts.Summaries());
    }

    [Fact]
    public async Task SwitchingChangesTheCurrentAccountOnlyToAStoredOne()
    {
        var accounts = AccountTestSupport.Manager(_server);
        await accounts.SignInAsync(_server);
        await accounts.SignInAsync(_server, "bob.test", BobDid);

        accounts.SwitchTo(AliceDid);

        Assert.Equal(Alice, accounts.CurrentAccount());
        var error = Assert.Throws<UnknownAccountException>(() => accounts.SwitchTo("did:plc:missing"));
        Assert.Equal("did:plc:missing", error.Did);
        Assert.Equal(Alice, accounts.CurrentAccount());
    }

    [Fact]
    public async Task SigningOutAdvancesToTheFirstRemainingAccount()
    {
        var accounts = AccountTestSupport.Manager(_server);
        await accounts.SignInAsync(_server);
        await accounts.SignInAsync(_server, "bob.test", BobDid);

        var next = accounts.RemoveAndAdvance(BobDid);

        Assert.Equal(AliceDid, next);
        Assert.Equal(Alice, accounts.CurrentAccount());
        Assert.Equal([Alice], accounts.Summaries());
    }

    [Fact]
    public async Task SigningOutOfTheLastAccountLeavesNoneCurrent()
    {
        var accounts = AccountTestSupport.Manager(_server);
        await accounts.SignInAsync(_server);

        var next = accounts.RemoveAndAdvance(AliceDid);

        Assert.Null(next);
        Assert.Null(accounts.CurrentAccount());
        Assert.Empty(accounts.Summaries());
        Assert.Throws<UnknownAccountException>(() => accounts.GetPds(AliceDid));
    }

    [Fact]
    public async Task AccountsSurviveARelaunchInTheDpapiStore()
    {
        if (!OperatingSystem.IsWindows()) return;
        var directory = Directory.CreateTempSubdirectory("yoru-accounts-").FullName;
        try
        {
            var before = AccountTestSupport.Manager(_server, new DpapiFileStorage(directory));
            await before.SignInAsync(_server);
            await before.SignInAsync(_server, "bob.test", BobDid);
            before.SwitchTo(AliceDid);

            var relaunched = AccountTestSupport.Manager(_server, new DpapiFileStorage(directory));

            Assert.Equal(Alice, relaunched.CurrentAccount());
            Assert.Equal([Alice, Bob], relaunched.Summaries());
            Assert.Equal(Pds, relaunched.GetPds(BobDid));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void TokenAndKeyHoldersDoNotPrintTheirSecrets()
    {
        var tokens = new OAuthTokens("secret-access", "secret-refresh", "atproto");
        var account = new StoredAccount(AliceDid, "alice.test", Pds, Issuer, tokens, [0x5e, 0xc2]);

        Assert.DoesNotContain("secret", tokens.ToString());
        Assert.DoesNotContain("secret", account.ToString());
        Assert.DoesNotContain("secret", Pkce.FromVerifier("secret-verifier").ToString());
    }
}
