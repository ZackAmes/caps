import { Account, RpcProvider, CallData } from "starknet";

const RPC = "https://api.cartridge.gg/x/starknet/sepolia/rpc/v0_9?key=sk_774507a993775cd33180e7d23300c532";
const ACTIONS = "0x595529996c02ab0520ceeba845944bc8be502ddb1678ffd313856a54a886baf";

const provider = new RpcProvider({ nodeUrl: RPC });
const account = new Account({
  provider,
  address: "0x0694182a014b39855a1b139961a3f39e7d4b43527b30d892a630d66a2abe3780",
  signer: "0x0430638cc3ef026ad7a74d9ad143bfc15bf303cea0be1c972ab1f280c90a531a",
});

// 1. Create a solo game (uses set_id 0 = set_zero)
const res = await account.execute(
  { contractAddress: ACTIONS, entrypoint: "create_solo_game", calldata: CallData.compile([]) },
  undefined,
  { tip: 0 }
);
console.log("create tx:", res.transaction_hash);
await provider.waitForTransaction(res.transaction_hash);

// 2. Find the game id (probe 1..10)
for (let id = 1; id <= 10; id++) {
  const raw = await provider.callContract({
    contractAddress: ACTIONS,
    entrypoint: "get_game",
    calldata: CallData.compile([id]),
  });
  const f = raw as unknown as string[];
  if (f[0] === "0") {
    console.log(`Game #${id} exists!`);
    // 3. Fetch cap type 1 (Striker) via get_cap_data
    const ct = await provider.callContract({
      contractAddress: ACTIONS,
      entrypoint: "get_cap_data",
      calldata: CallData.compile([id, 1]),
    });
    console.log("Striker CapType raw:", ct.slice(0, 8));
    // 4. Fetch hand
    const hand = await provider.callContract({
      contractAddress: ACTIONS,
      entrypoint: "get_hand",
      calldata: CallData.compile([id, 0]),
    });
    console.log("P1 hand:", (hand as string[]).slice(0, 12).join(","));
    break;
  }
}
