# Token-Staking

# Deploy
PUBLISHER_PROFILE=testnet && \
PUBLISHER_ADDR=0x7aa73748449edb3328d6629707c39a5dbddf649e2b630084efcb4dbee2e4ce24 && \
aptos move create-object-and-publish-package \
--address-name slime \
--named-addresses \
deployer=$PUBLISHER_ADDR \
--profile $PUBLISHER_PROFILE \
--assume-yes --included-artifacts none

# Upgrade
PUBLISHER_PROFILE=testnet && \
PUBLISHER_ADDR=0x7aa73748449edb3328d6629707c39a5dbddf649e2b630084efcb4dbee2e4ce24  && \
OBJECT_ADDR="0x3d5ee844b09339cfa59c2bbb461c614e289160b15c5d56e0a595f2cf4296b7a5" && \
aptos move upgrade-object-package \
--object-address $OBJECT_ADDR \
--named-addresses \
slime=$OBJECT_ADDR,deployer=$PUBLISHER_ADDR --profile $PUBLISHER_PROFILE \
--assume-yes --included-artifacts none