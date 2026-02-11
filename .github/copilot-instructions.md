# Copilot Instructions for sonic-alpine

## Project Overview

sonic-alpine is the build system for AlpineVS, an alternative SONiC virtual switch platform that uses LemmingSAI (a P4-based SAI implementation from Google) instead of the traditional virtual switch SAI. It integrates into the sonic-buildimage build framework as a platform plugin.

## Architecture

```
sonic-alpine/
├── alpine-config.mk/.dep      # Build rules for Alpine platform configuration
├── alpine-device.mk/.dep      # Device/HwSKU data rules
├── alpine-init.mk/.dep        # Platform initialization rules
├── docker-syncd-vs.mk/.dep    # Syncd container build with LemmingSAI
├── docker-syncd-vs/            # Dockerfile and assets for VS syncd
├── kvm-image.mk/.dep          # KVM image build rules
├── lemmingsai.mk/.dep         # LemmingSAI SAI library build
├── one-image.mk/.dep          # ONIE image build rules
├── onie.mk/.dep               # ONIE installer rules
├── .gitmodules                 # Git submodule references
└── README.md
```

### Key Concepts
- **Platform plugin**: sonic-alpine acts as a platform definition within sonic-buildimage
- **LemmingSAI**: P4-based SAI implementation providing a behavioral model for switch ASIC simulation
- **.mk/.dep pattern**: Each component has a `.mk` (build rules) and `.dep` (dependencies) file pair
- **Integrates with sonic-buildimage**: Must be built within the sonic-buildimage framework

## Build Instructions

```bash
# Clone sonic-buildimage
git clone https://github.com/sonic-net/sonic-buildimage.git
cd sonic-buildimage

# Initialize (skip older Debian versions)
export NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 NOBOOKWORM=0 NOTRIXIE=0
make init

# Optional: enable P4RT and gNMI
echo "INCLUDE_P4RT = y" >> rules/config.user
echo "INCLUDE_SYSTEM_GNMI = y" >> rules/config.user
echo "ENABLE_TRANSLIB_WRITE = y" >> rules/config.user

# Configure for AlpineVS platform
PLATFORM=alpinevs make configure

# Build targets
make target/sonic-alpinevs.img.gz          # KVM image
./alpine/build_alpinevs_container.sh       # Container image
```

## Language & Style

- **Primary language**: Shell (Makefiles), with integration into the GNU Make build system
- **Makefile conventions**: Follow sonic-buildimage patterns for `.mk`/`.dep` files
- **Variable naming**: `UPPER_CASE` for Make variables
- **Dependencies**: Declare all dependencies in `.dep` files

## PR Guidelines

- **Signed-off-by**: Required on all commits
- **CLA**: Sign Linux Foundation EasyCLA
- **Testing**: Verify the AlpineVS image builds successfully within sonic-buildimage
- **Single commit per PR**: Squash before merge

## Gotchas

- **Must build within sonic-buildimage**: This repo cannot be built standalone
- **LemmingSAI compatibility**: Changes must be compatible with the LemmingSAI P4 behavioral model
- **Platform vs generic**: Changes here only affect the AlpineVS platform, not other SONiC platforms
- **Submodule references**: Keep `.gitmodules` in sync when updating dependencies
