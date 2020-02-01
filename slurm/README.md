## flux-infect.lua

The flux-infect.lua Slurm plugin runs all Slurm batch jobs under
`srun -n $SLURM_NNODES -N $SLURM_NNODES flux start` by wrapping
all user's job scripts. This can be disabled by a `--without-flux`
option. Options to `flux start` can be passed via a `--flux-options`
option.
