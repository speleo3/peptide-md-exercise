all:
	bash script.sh

clean:
	$(RM) "#"*

distclean:
	$(RM) "#"* *.gro *.top *.itp *.tpr mdout.mdp
