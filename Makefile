.PHONY: vagrant
vagrant:
	vagrant halt
	vagrant destroy -f
	packer build -force -only=vagrant.* -var environment=development -var region=us-east-1 base_image.pkr.hcl
	vagrant box add --force --name test-debian output-debian/package.box
	vagrant up
