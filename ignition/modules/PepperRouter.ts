import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const FEE_COLLECTOR = "0x475e053c171ff06fe555e536ff85148f6b053d29";
const PepperRouterModule = buildModule("PepperRouterModule", (m) => {
  const feeTo = m.getParameter("feeTo", FEE_COLLECTOR);
  const PepperRouter = m.contract("PepperRouter", [feeTo]);
  return { PepperRouter };
});

export default PepperRouterModule;
