task("activate-withdrawals", "Allow unstaking")
	.setAction(async (taskArgs) => {

		const LiquidStakingControllerFactory = await ethers.getContractFactory("LiquidStakingController");
		const LiquidStakingControllerDeployment = await hre.deployments.get("LiquidStakingController");
		const controller = LiquidStakingControllerFactory.attach(LiquidStakingControllerDeployment.address);

		try {
			await controller.activateWithdrawals();

			console.log("withdrawals activated");
		} catch (e) {
			console.log(e);
		}
	});

module.exports = {};
