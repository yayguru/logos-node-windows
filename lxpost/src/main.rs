// SPDX-License-Identifier: MIT OR Apache-2.0
//! lxpost: build + sign an LXM1 inscription tx funded by the node wallet.
//! Steps (HTTP done by the caller with curl):
//!   lxpost fund-req  <sender_seed_file> <inscription_hex> <funding_pk_hex> <max_fee> [parent_msg_id] -> /wallet/fund body
//!   lxpost sign      <sender_seed_file> <fund_response.json>                         -> /mempool/add/tx body
//! The sender key is a dedicated Ed25519 channel key (never a wallet/stake key).
use lb_api::bodies::wallet::fund::{WalletFundRequestBody, WalletFundResponseBody};
use lb_core::mantle::{
    SignedOps, ops::{Op, OpProof, OpRef, channel::{ChannelId, MsgId, inscribe::InscriptionOp}},
    traits::{Hashable as _, MantleTx as _}, transactions::{MantleTxBuilder, OpProofs},
};
use lb_keys::keys::Ed25519Key;
use sha2::{Digest, Sha256};
use std::env;
use lb_core::mantle::{gas::{TxGasCalculator, MainnetGasProfile}, transactions::{GasPrices, tx_list::ops::OpsGasContext}};
use std::collections::HashMap;

/// Inscription payload argument: "@path" = raw bytes of that file, otherwise hex.
fn payload(a: &str) -> Vec<u8> {
    if let Some(p) = a.strip_prefix('@') { std::fs::read(p).expect("cannot read payload file") } else { hex::decode(a).expect("bad hex") }
}

fn key(path: &str) -> Ed25519Key {
    let j: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let b: [u8; 32] = hex::decode(j["ed25519_seed"].as_str().unwrap()).unwrap().try_into().unwrap();
    Ed25519Key::from_bytes(&b)
}
fn main() {
    let a: Vec<String> = env::args().collect();
    match a[1].as_str() {
        "fund-req" => {
            if a[4].starts_with("760456") { panic!("refusing: stake key"); }
            let k = key(&a[2]);
            let pk = k.public_key();
            let cid: [u8; 32] = Sha256::new().chain_update(b"LXM1").chain_update(pk.as_bytes()).finalize().into();
            let op = InscriptionOp { channel_id: ChannelId::from(cid), inscription: payload(&a[3]).try_into().expect("payload too large (max 1835008 bytes)"),
                parent: a.get(6).map(|h| MsgId::from(<[u8;32]>::try_from(hex::decode(h).unwrap()).unwrap())).unwrap_or(MsgId::root()), signer: pk.into_unverified() };
            eprintln!("channel_id={} msg_id={} signer={}", hex::encode(cid), op.id(), hex::encode(pk.as_bytes()));
            let body = WalletFundRequestBody { tip: None, tx_builder: MantleTxBuilder::new().extend_ops(vec![Op::ChannelInscribe(op)]).unwrap(),
                change_public_key: serde_json::from_value(serde_json::json!(a[4])).unwrap(),
                funding_public_keys: vec![serde_json::from_value(serde_json::json!(a[4])).unwrap()],
                max_tx_fee: serde_json::from_value(serde_json::json!(a[5].parse::<u64>().unwrap())).unwrap(), priority_fee_percent: 12 };
            println!("{}", serde_json::to_string(&body).unwrap());
        }
        "sign" => {
            let k = key(&a[2]);
            let r: WalletFundResponseBody = serde_json::from_str(&std::fs::read_to_string(&a[3]).unwrap()).unwrap();
            let tx = r.funded_tx;
            let h = tx.hash();
            let sig = k.sign_payload(h.as_signing_bytes());
            let mut proofs = OpProofs::empty();
            for op in tx.op_refs() { match op {
                OpRef::ChannelInscribe(_) => proofs.try_push(OpProof::Ed25519Sig(sig)).unwrap(),
                OpRef::Transfer(_) => proofs.try_push(r.transfer_proof.clone().expect("no transfer proof")).unwrap(),
                o => panic!("unexpected op {o:?}"),
            }}
            eprintln!("tx_hash={h}");
            let s: SignedOps<lb_core::mantle::transactions::states::Unverified, lb_core::mantle::ledger::verification_mode::StandardMode> = SignedOps::from_parts(tx, proofs).expect("unprovable");
            println!("{}", serde_json::to_string(&s).unwrap());
        }
        "transfer-req" => {
            // transfer-req <recipient_pk> <amount> <from_pk> <max_fee>  -> /wallet/fund body (preview only; nothing is sent)
            use lb_core::mantle::ledger::Note;
            let rcp: lb_keys::keys::ZkPublicKey = serde_json::from_value(serde_json::json!(a[2])).expect("bad recipient key");
            let note = Note::new(a[3].parse::<u64>().expect("bad amount"), rcp);
            let body = WalletFundRequestBody { tip: None, tx_builder: MantleTxBuilder::new().add_ledger_output(note).unwrap(),
                change_public_key: serde_json::from_value(serde_json::json!(a[4])).unwrap(),
                funding_public_keys: vec![serde_json::from_value(serde_json::json!(a[4])).unwrap()],
                max_tx_fee: serde_json::from_value(serde_json::json!(a[5].parse::<u64>().unwrap())).unwrap(), priority_fee_percent: 0 };
            println!("{}", serde_json::to_string(&body).unwrap());
        }
        "keygen" => {
            // keygen <file>: new random Ed25519 channel key (seed file, never printed). Refuses to overwrite.
            let mut seed = [0u8; 32]; getrandom::getrandom(&mut seed).expect("no OS randomness");
            let pk = Ed25519Key::from_bytes(&seed).public_key();
            let mut f = std::fs::OpenOptions::new().write(true).create_new(true).open(&a[2]).expect("key file exists or cannot be created");
            use std::io::Write as _;
            f.write_all(serde_json::json!({"ed25519_seed": hex::encode(seed), "public": hex::encode(pk.as_bytes())}).to_string().as_bytes()).unwrap();
        }
        "ident" => {
            let pk = key(&a[2]).public_key();
            let cid: [u8; 32] = Sha256::new().chain_update(b"LXM1").chain_update(pk.as_bytes()).finalize().into();
            println!("{}", serde_json::json!({"signer": hex::encode(pk.as_bytes()), "channel_id": hex::encode(cid)}));
        }
        "info" => {
            // info <fund_response.json> <exec_price> <storage_price>
            let r: WalletFundResponseBody = serde_json::from_str(&std::fs::read_to_string(&a[2]).unwrap()).unwrap();
            let ctx = OpsGasContext::new(HashMap::new(), HashMap::new(), GasPrices::new(a[3].parse().unwrap(), a[4].parse().unwrap()));
            let ops = r.funded_tx.by_ref();
            let total = ops.total_gas_cost::<MainnetGasProfile>(&ctx).unwrap();
            let eg = ops.execution_gas_consumption::<MainnetGasProfile>(&ctx).unwrap();
            let sg = ops.storage_gas_consumption(&ctx).unwrap();
            println!("{}", serde_json::json!({"mandatory_fee": serde_json::to_value(&total).unwrap(), "execution_gas": serde_json::to_value(&eg).unwrap(), "storage_gas_bytes": serde_json::to_value(&sg).unwrap()}));
        }
        _ => panic!("usage"),
    }
}
