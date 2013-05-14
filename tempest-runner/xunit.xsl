<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:template match="/">
        <html>
            <body>
                <code>
                    <p><strong>Tests: <xsl:value-of select="testsuite/@tests"/>, errors <xsl:value-of select="testsuite/@errors"/>,
                            failures <xsl:value-of select="testsuite/@failures"/>, skip <xsl:value-of select="testsuite/@skip"/>.</strong></p>
                    <p></p>
                    <table border="0">
                        <tr bgcolor="#eeeeee">
                            <th>STATUS</th>
                            <th>Class, testname, Time, Message</th>
                            <th>Stacktrace</th>
                        </tr>
                        <xsl:for-each select="testsuite/testcase">
                            <xsl:choose>
                                <xsl:when test="skipped != ''">
                                    <tr bgcolor="gray">
                                        <td>
                                            SKIP
                                        </td>
                                        <td>
                                            <p>Class: <xsl:value-of select = "@classname"/></p>
                                            <p>Test: <xsl:value-of select = "@name"/></p>
                                            <p>Time:<xsl:value-of select = "@time"/></p>
                                            <p>=========================================</p>
                                            <pre width="100"><xsl:value-of select = "./skipped/@message"/></pre>
                                        </td>
                                        <td>
                                            <pre width="100"><xsl:value-of select = "./skipped"/></pre>
                                        </td>
                                    </tr>
                                </xsl:when>
                                <xsl:when test="error != ''">
                                    <tr bgcolor="chucknorris">
                                        <td>
                                            ERROR
                                        </td>
                                        <td>
                                            <p>Class: <xsl:value-of select = "@classname"/></p>
                                            <p>Test: <xsl:value-of select = "@name"/></p>
                                            <p>Time:<xsl:value-of select = "@time"/></p>
                                            <p>=========================================</p>
                                            <pre width="100"><xsl:value-of select = "./error/@message"/></pre>
                                        </td>
                                        <td>
                                            <pre width="100"><xsl:value-of select = "./error"/></pre>
                                        </td>
                                    </tr>
                                </xsl:when>
                                <xsl:when test="failure != ''">
                                    <tr bgcolor="orange">
                                        <td>
                                            FAIL
                                        </td>
                                        <td>
                                            <p>Class: <xsl:value-of select = "@classname"/></p>
                                            <p>Test: <xsl:value-of select = "@name"/></p>
                                            <p>Time:<xsl:value-of select = "@time"/></p>
                                            <p>=========================================</p>
                                            <pre width="100"><xsl:value-of select = "./failure/@message"/></pre>
                                        </td>
                                        <td>
                                            <pre width="100"><xsl:value-of select = "./failure"/></pre>
                                        </td>
                                    </tr>
                                </xsl:when>
                                <xsl:otherwise>
                                    <tr bgcolor="budda">
                                        <td>
                                            OK
                                        </td>
                                        <td>
                                            <p>Class: <xsl:value-of select = "@classname"/></p>
                                            <p>Test: <xsl:value-of select = "@name"/></p>
                                            <p>Time:<xsl:value-of select = "@time"/></p>
                                        </td>
                                        <td>-</td>
                                    </tr>
                                </xsl:otherwise>
                            </xsl:choose>
                        </xsl:for-each>
                    </table>
                </code>
            </body>
        </html>
    </xsl:template>
</xsl:stylesheet>
