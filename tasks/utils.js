const util = require("util");
const request = util.promisify(require("request"));

export function hexToBytes(hex) {
	for (var bytes = [], c = 0; c < hex.length; c += 2) bytes.push(parseInt(hex.substr(c, 2), 16));
	return new Uint8Array(bytes);
}

export async function callRpc(method, params) {
	var options = {
		method: "POST",
		url: "https://filecoin-mainnet.chainstacklabs.com/rpc/v1",
		headers: {
			"Content-Type": "application/json",
		},
		body: JSON.stringify({
			jsonrpc: "2.0",
			method: method,
			params: params,
			id: 1,
		}),
	};
	const res = await request(options);
	return JSON.parse(res.body).result;
}
