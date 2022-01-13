import { expect } from "chai";
import { ethers } from "hardhat";

describe("Dikasteria Token", function () {
  it("Should deploy with correct params", async function () {
    const Dikasteria = await ethers.getContractFactory("Dikasteria");
    const dikasteriaInstance = await Dikasteria.deploy();
    await dikasteriaInstance.deployed();

    const totalSupply = await dikasteriaInstance.totalSupply();

    expect(await dikasteriaInstance.name()).to.equal("Dikasteria");
    expect(await dikasteriaInstance.symbol()).to.equal("DIKA");
    expect(totalSupply.toString()).to.equal("69420000");
  });
});
