#! /usr/bin/bash

#SBATCH --partition=cpu-single
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:15:00
#SBATCH --mem=100gb

module load math/R
module load devel/miniforge

conda activate r_env

echo "[$(date '+%H:%M:%S')] Starting SEHTestACS2a_dataprepACS.R"
Rscript SEHTestACS2a_dataprepACS.R
echo "[$(date '+%H:%M:%S')] Starting SEHTestACS2b_dataprepPUMS.R"
Rscript SEHTestACS2b_dataprepPUMS.R
echo "[$(date '+%H:%M:%S')] Starting SEHTestACS3_citylevel.R"
Rscript SEHTestACS3_citylevel.R
echo "[$(date '+%H:%M:%S')] Done"
