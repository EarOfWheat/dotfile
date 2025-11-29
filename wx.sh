tmux new -d -As wx
tmux send -t wx "cd" Enter
tmux send -t wx "docker run -it -p 3001:3001 -v ./config:/config nickrunning/wechat-selkies:latest" Enter
tmux switchc -t wx
