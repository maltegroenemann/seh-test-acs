#! /usr/bin/bash

#SBATCH --partition=cpu-single
#SBATCH --ntasks=1
#SBATCH --time=00:15:00
#SBATCH --mem=50gb

module load math/R
module load devel/miniforge

conda activate r_env

#echo "[$(date '+%H:%M:%S')] Starting SEHTestACS5_description.Rmd"
#Rscript -e "rmarkdown::render('SEHTestACS5_description.Rmd')"

echo "[$(date '+%H:%M:%S')] Starting SEHTestACS6a_housingseg.Rmd"
Rscript -e "rmarkdown::render('SEHTestACS6a_housingseg.Rmd')"

echo "[$(date '+%H:%M:%S')] Starting SEHTestACS6b_housinginequality.Rmd"
Rscript -e "rmarkdown::render('SEHTestACS6b_housinginequality.Rmd')"

echo "[$(date '+%H:%M:%S')] Starting SEHTestACS6c_vacancy.Rmd"
Rscript -e "rmarkdown::render('SEHTestACS6c_vacancy.Rmd')"

#echo "[$(date '+%H:%M:%S')] Starting SEHTestACS6d_quality.Rmd"
#Rscript -e "rmarkdown::render('SEHTestACS6d_quality.Rmd')"

#echo "[$(date '+%H:%M:%S')] Starting SEHTestACS6e_tenure.Rmd"
#Rscript -e "rmarkdown::render('SEHTestACS6e_tenure.Rmd')"

echo "[$(date '+%H:%M:%S')] Done"
