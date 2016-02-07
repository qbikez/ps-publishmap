module.exports = function (grunt) {
    grunt.initConfig({
        shell: {
            test: {
                options: {
                    stdout: true
                },
                command: 'powershell scripts\\test.ps1'
            }
        }
    });

    grunt.loadNpmTasks('grunt-shell');
    
    grunt.registerTask('test', ['shell:test']);
}