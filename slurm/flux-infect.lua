--
--  Slurm spank/lua plugin which runs all Slurm batch jobs under a
--  flux instance by wrapping user's job script in flux-start(1).
--
-- ===========================================================================
--
-- Plugin options:
spank_options = {
    {
        name =    "without-flux",
        usage =   "Disable automatic Flux instance for batch jobs",
        val   =   1,
        has_arg = false,
        opt_handler = "opt_handler",
    },
    {
        name =    "flux-options",
        usage =   "Pass extra options to flux-start",
        val =      2,
        has_arg =  1,
        arginfo = "OPTS...",
        opt_handler = "opt_handler",
    },
}

-- Local getopt() function to work around possible broken
-- option forwarding from sbatch to batch jobs. First check using
-- sp:getopt() then fall back to checking for a spank-specific
-- environment variable that Slurm happens to leak into the user
-- env. N.B.: this probably depends on buggy Slurm behavior and may
-- break at any time:
--
local function get_option_info (opts, name)
    for _,entry in ipairs (opts) do
        if entry.name == name then
            return {
                opt = entry,
                env = "SLURM_SPANK__SLURM_SPANK_OPTION_lua_"..
                       name:gsub ('-','_')
            }
        end
    end
    return nil
end

local function getopt (sp, name)
    local info = get_option_info (spank_options, name)
    if not info then return nil end
    return sp:getopt (info.opt) or sp:getenv (info.env)
end

local function runcmd (fmt, ...)
    local cmd = string.format (fmt, ...)
    --SPANK.log_info ("Running %s", cmd)
    return os.execute (cmd)
end

-- Return true only if this is a batch job step in remote context.
-- XXX: relies on non-exported special job stepid for batch jobs of 2^32-2
--
local function is_batch_step (sp)
    if sp.context ~= "remote" then return false end
    local stepid = sp:get_item ("S_JOB_STEPID")
    return stepid == 2^32-2
end

-- Generate path to the slurm_script for this job.
-- XXX: Path gleaned from slurm source, and could change at any time
--
local function batch_script_path (sp)
    local spooldir  = "/var/spool/slurmd";
    local jobid = sp:get_item ("S_JOB_ID")
    local script = string.format ("%s/job%05u/slurm_script", spooldir, jobid)
    return script
end

-- Create a wrapper script that invokes Slurm batch script `orig`
--  under flux-start with extra options in `opts`:
--
local function wrap_batch_script (script, orig, opts)
    local f,err = io.open (script, "w");
    if not f then
        SPANK.log_err ("unable to open %s: %s", script, err)
        return nil, err
    end
    f:write ("#!/bin/sh\n")
    f:write (string.format ("srun --mpi=none " ..
                            "-N$SLURM_NNODES " ..
                            "-n$SLURM_NNODES " ..
                            "flux start %s %s\n",
                            opts or "",
                            orig))
    f:close()
    runcmd ("chmod 755 %s", script)
    return true
end

function slurm_spank_init_post_opt (sp)
    if not is_batch_step (sp) or getopt (sp, "no-flux") then
        return SPANK.SUCCESS
    end
    local script = batch_script_path (sp)
    local orig = script .. ".user"
    runcmd ("mv %s %s", script, orig)
    return wrap_batch_script (script, orig, getopt (sp, "flux-options"));
end

function slurm_spank_exit (sp)
    if not is_batch_step (sp) or getopt (sp, "no-flux") then
        return SPANK.SUCCESS
    end
    local script = batch_script_path (sp);
    runcmd ("rm %s.user", script)
end

-- vi: ts=4 sw=4 expandtab
