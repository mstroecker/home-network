scp ~/.ssh/id_rsa.pub admin@192.168.89.1:sshkey.pub
ssh admin@192.168.89.1 '/user ssh-keys import public-key-file=sshkey.pub user=admin'
