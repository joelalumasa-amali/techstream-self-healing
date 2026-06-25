
@app.route('/restart')
def restart():
    import subprocess
    subprocess.Popen(['sudo', 'systemctl', 'restart', 'techstream'])
    return jsonify({'restarted': True})
